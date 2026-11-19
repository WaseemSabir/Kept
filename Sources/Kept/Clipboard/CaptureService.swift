import AppKit
import KeptCore

/// Turns pasteboard changes into history: reads the pasteboard (policy
/// first), builds the clip and writes its blob files off the main actor,
/// and records it.
///
/// A copy is skipped before anything is read if an excluded app was
/// frontmost at any moment since the previous poll (`AppActivationLog`),
/// not only at the poll, so a password manager that copies and hands focus
/// straight back isn't mistaken for the app it returned to. The clip is
/// checked again before it's recorded, once activations whose
/// notifications were queued behind the poll have been logged.
///
/// At most `maxBuildsInFlight` builds run at once, so a slow one (a huge
/// image) doesn't hold up the copy after it, and a burst of copies can't
/// pile up snapshots and threads. A copy read while every build is busy
/// waits for one to finish; a newer copy replaces it, so the newest copy
/// is always recorded. Blob files are written on the stager's own queue.
/// Each clip is recorded with the time its copy was seen, and the store
/// orders clips by that time, so builds may finish in any order. A build
/// that finishes after the history was cleared or its clip deleted, or
/// after capture was paused, its app excluded or its kind turned off, is
/// dropped, and its blob files with it.
@MainActor
final class CaptureService {
    /// Reads the pasteboard: `PasteboardReader` unless a test stands in.
    typealias Read = @MainActor (NSPasteboard, CaptureSettings, _ frontmostBundleID: String?) -> PasteboardReader.ReadResult

    /// How many builds may run at once.
    static let maxBuildsInFlight = 2

    private enum BuildOutcome: Sendable {
        /// Nothing worth keeping (see `ClipBuilder.build(from:)`).
        case nothing
        case staged(StagedClip)
        /// Staging failed; `written` holds the files it wrote before then.
        case failed(HistoryStoreError, written: StagedClip)
    }

    /// A copy read from the pasteboard, to be built.
    private struct Copy: Sendable {
        let snapshot: PasteboardSnapshot
        /// The settings when it was read; the build follows them.
        let settings: CaptureSettings
        let facts: Facts
    }

    /// What's checked again once a copy's clip is built.
    private struct Facts: Sendable {
        let declaredTypes: [PasteboardType]
        let copiedAt: Date
        /// The store's `clearGeneration` when the copy was seen.
        let generation: Int
        /// When the copy's window opened and when it was polled, on the
        /// activation log's clock; `nil` when activations aren't followed.
        let window: (start: Double, poll: Double)?
    }

    private let pasteboard: NSPasteboard
    private let store: HistoryStore
    private let settings: @MainActor () -> CaptureSettings
    private let activations: AppActivationTracker?
    private let read: Read
    private let willBuild: @Sendable (PasteboardSnapshot) async -> Void
    private var builds: [Int: Task<Void, Never>] = [:]
    private var nextBuildID = 0
    /// The newest copy read while every build was busy.
    private var waiting: Copy?

    /// - Parameters:
    ///   - activations: which apps were frontmost lately; `nil` checks only
    ///     the app in front at the poll.
    ///   - read: reads the pasteboard; tests replace it.
    ///   - willBuild: runs off the main actor before each build; tests use
    ///     it to hold builds back.
    init(
        pasteboard: NSPasteboard = .general,
        store: HistoryStore,
        settings: @escaping @MainActor () -> CaptureSettings,
        activations: AppActivationTracker? = nil,
        read: Read? = nil,
        willBuild: @escaping @Sendable (PasteboardSnapshot) async -> Void = { _ in }
    ) {
        self.pasteboard = pasteboard
        self.store = store
        self.settings = settings
        self.activations = activations
        if let read {
            self.read = read
        } else {
            self.read = { pasteboard, settings, frontmost in
                PasteboardReader().read(from: pasteboard, settings: settings, frontmostBundleID: frontmost)
            }
        }
        self.willBuild = willBuild
    }

    /// Reads what's on the pasteboard now and records it unless it's ignored.
    ///
    /// - Parameter windowStart: when the pasteboard was last seen unchanged
    ///   (`PasteboardMonitor.previousPollTime`); the copy was made after it.
    ///   `nil` checks only the app in front now.
    func captureCurrentContents(since windowStart: Double? = nil) {
        let settings = settings()
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let copiedAt = Date()

        var window: (start: Double, poll: Double)?
        if let activations {
            let now = AppActivationTracker.now()
            window = (windowStart ?? now, now)
            if !settings.isPaused,
               let app = activations.log.excludedApp(from: windowStart ?? now, through: now, settings: settings) {
                Log.capture.debug("Skipped a copy: \(app, privacy: .public) was in front since the last check")
                return
            }
        }

        switch read(pasteboard, settings, frontmost) {
        case .ignored(let reason):
            Log.capture.debug("Skipped a copy: \(String(describing: reason), privacy: .public)")

        case .changedDuringRead:
            Log.capture.debug("The pasteboard changed while it was read; the next poll takes the new copy.")

        case .snapshot(let snapshot):
            let facts = Facts(
                declaredTypes: snapshot.allTypes,
                copiedAt: copiedAt,
                generation: store.clearGeneration,
                window: window
            )
            enqueue(Copy(snapshot: snapshot, settings: settings, facts: facts))
        }
    }

    /// Waits for every build started so far, and the copy waiting for one
    /// (for tests).
    func waitUntilIdle() async {
        while let build = builds.values.first {
            await build.value
        }
    }

    /// Builds `copy` now if a build is free; otherwise it waits, replacing
    /// any copy already waiting.
    private func enqueue(_ copy: Copy) {
        guard builds.count >= Self.maxBuildsInFlight else {
            startBuild(of: copy)
            return
        }
        if waiting != nil {
            Log.capture.debug("Skipped a copy: a newer one came before a build was free")
        }
        waiting = copy
    }

    /// Normalizes, builds and stages the clip (blob files written and
    /// flushed on the stager's queue) in a detached task, then records it on
    /// the main actor, no sooner than activations from before its poll have
    /// all been logged.
    private func startBuild(of copy: Copy) {
        let builder = ClipBuilder(settings: copy.settings, imageInspector: ImageIOInspector())
        let stager = store.stager
        let willBuild = willBuild
        let snapshot = copy.snapshot
        let facts = copy.facts
        let id = nextBuildID
        nextBuildID += 1
        builds[id] = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { () async -> BuildOutcome in
                await willBuild(snapshot)
                guard let draft = builder.build(from: PasteboardReader.normalized(snapshot)) else { return .nothing }
                do throws(ClipStager.Failure) {
                    return .staged(try await stager.stageInBackground(draft))
                } catch {
                    return .failed(error.error, written: error.written)
                }
            }.value
            if let window = facts.window {
                await Self.waitUntilSettled(afterPollAt: window.poll)
            }
            self?.finishBuild(id, outcome, facts)
        }
    }

    /// Returns once `AppActivationLog.settledTime(afterPollAt:)` has passed.
    private nonisolated static func waitUntilSettled(afterPollAt pollTime: Double) async {
        let remaining = AppActivationLog.settledTime(afterPollAt: pollTime) - AppActivationTracker.now()
        guard remaining > 0 else { return }
        try? await Task.sleep(for: .seconds(remaining))
    }

    private func finishBuild(_ id: Int, _ outcome: BuildOutcome, _ facts: Facts) {
        builds[id] = nil
        if let next = waiting {
            waiting = nil
            startBuild(of: next)
        }

        let staged: StagedClip
        switch outcome {
        case .nothing:
            return
        case .failed(let error, let written):
            Log.capture.error("Couldn't store a clip: \(String(describing: error), privacy: .public)")
            store.discard(written)
            return
        case .staged(let clip):
            staged = clip
        }

        if let reason = dropReason(for: staged.draft, facts) {
            Log.capture.debug("Dropped a finished capture: \(reason, privacy: .public)")
            store.discard(staged)
            return
        }
        // A slow build can finish after the same content was copied again
        // and recorded; recording it now would move that clip back in time.
        if let existing = store.clip(withContentHash: staged.draft.contentHash),
           existing.lastCopiedAt > facts.copiedAt {
            store.discard(staged)
            return
        }
        do {
            try store.record(staged, at: facts.copiedAt)
        } catch {
            Log.capture.error("Couldn't record a clip: \(String(describing: error), privacy: .public)")
        }
    }

    /// Why a clip that finished building mustn't be recorded after all: the
    /// history was cleared or the clip deleted since its copy was seen, an
    /// excluded app turned out to be in front around the copy, or meanwhile
    /// capture was paused, its app excluded or its kind turned off. `nil`
    /// when it's still wanted.
    private func dropReason(for draft: ClipDraft, _ facts: Facts) -> String? {
        guard store.clearGeneration == facts.generation else { return "the history was cleared" }
        if store.wasDeleted(draft.contentHash, after: facts.copiedAt) { return "it was deleted meanwhile" }
        let settings = settings()
        if !settings.isPaused, let activations, let window = facts.window,
           let app = activations.log.excludedApp(from: window.start, polledAt: window.poll, settings: settings) {
            return "\(app) was in front around the copy"
        }
        let decision = CapturePolicy(settings: settings).decision(types: facts.declaredTypes, sourceBundleID: draft.sourceBundleID)
        if case .ignore(let reason) = decision { return String(describing: reason) }
        switch draft.kind {
        case .image where !settings.captureImages: return "images are no longer kept"
        case .file where !settings.captureFiles: return "files are no longer kept"
        default: return nil
        }
    }
}
