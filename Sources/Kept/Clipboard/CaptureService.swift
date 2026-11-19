import AppKit
import KeptCore

/// Turns pasteboard changes into history: reads the pasteboard (policy
/// first), builds the clip and writes its blob files off the main actor,
/// and records it.
///
/// A copy is skipped before anything is read if an excluded app was
/// frontmost at any moment since the previous poll (`AppActivationLog`),
/// not only at the poll, so a password manager that copies and hands focus
/// straight back isn't mistaken for the app it returned to.
///
/// Builds run side by side, so a slow one (a huge image) never holds up
/// the copies after it. Each clip is recorded with the time its copy was
/// seen, and the store orders clips by that time, so builds may finish in
/// any order. A build that finishes after the history was cleared, capture
/// was paused, its app was excluded or its kind turned off is dropped, and
/// its blob files with it.
@MainActor
final class CaptureService {
    /// Reads the pasteboard: `PasteboardReader` unless a test stands in.
    typealias Read = @MainActor (NSPasteboard, CaptureSettings, _ frontmostBundleID: String?) -> PasteboardReader.ReadResult

    private enum BuildOutcome: Sendable {
        /// Nothing worth keeping (see `ClipBuilder.build(from:)`).
        case nothing
        case staged(StagedClip)
        case failed(any Error)
    }

    private let pasteboard: NSPasteboard
    private let store: HistoryStore
    private let settings: @MainActor () -> CaptureSettings
    private let activations: AppActivationTracker?
    private let read: Read
    private let willBuild: @Sendable (PasteboardSnapshot) async -> Void
    private var builds: [Int: Task<Void, Never>] = [:]
    private var nextBuildID = 0

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

        if !settings.isPaused, let activations {
            let now = AppActivationTracker.now()
            if let app = activations.log.excludedApp(from: windowStart ?? now, through: now, settings: settings) {
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
            startBuild(of: snapshot, settings: settings, copiedAt: copiedAt)
        }
    }

    /// Waits for every build started so far (for tests).
    func waitUntilIdle() async {
        while let build = builds.values.first {
            await build.value
        }
    }

    /// Normalizes, builds and stages the clip (blob files written and
    /// flushed) in a detached task, then records it on the main actor.
    private func startBuild(of snapshot: PasteboardSnapshot, settings: CaptureSettings, copiedAt: Date) {
        let builder = ClipBuilder(settings: settings, imageInspector: ImageIOInspector())
        let stager = store.stager
        let willBuild = willBuild
        let generation = store.clearGeneration
        let declaredTypes = snapshot.allTypes
        let id = nextBuildID
        nextBuildID += 1
        builds[id] = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) { () async -> BuildOutcome in
                await willBuild(snapshot)
                guard let draft = builder.build(from: PasteboardReader.normalized(snapshot)) else { return .nothing }
                do {
                    return .staged(try stager.stage(draft))
                } catch {
                    return .failed(error)
                }
            }.value
            self?.finishBuild(id, outcome, declaredTypes: declaredTypes, copiedAt: copiedAt, generation: generation)
        }
    }

    private func finishBuild(
        _ id: Int,
        _ outcome: BuildOutcome,
        declaredTypes: [PasteboardType],
        copiedAt: Date,
        generation: Int
    ) {
        builds[id] = nil
        let staged: StagedClip
        switch outcome {
        case .nothing:
            return
        case .failed(let error):
            Log.capture.error("Couldn't store a clip: \(String(describing: error), privacy: .public)")
            return
        case .staged(let clip):
            staged = clip
        }

        if let reason = dropReason(for: staged.draft, declaredTypes: declaredTypes, generation: generation) {
            Log.capture.debug("Dropped a finished capture: \(reason, privacy: .public)")
            store.discard(staged)
            return
        }
        // A slow build can finish after the same content was copied again
        // and recorded; recording it now would move that clip back in time.
        let contentHash = staged.draft.contentHash
        let existing = store.pinned.first { $0.contentHash == contentHash }
            ?? store.recent.first { $0.contentHash == contentHash }
        if let existing, existing.lastCopiedAt > copiedAt {
            store.discard(staged)
            return
        }
        do {
            try store.record(staged, at: copiedAt)
        } catch {
            Log.capture.error("Couldn't record a clip: \(String(describing: error), privacy: .public)")
        }
    }

    /// Why a clip that finished building mustn't be recorded after all: the
    /// history was cleared since its copy was seen, or meanwhile capture was
    /// paused, its app excluded or its kind turned off. `nil` when it's
    /// still wanted.
    private func dropReason(for draft: ClipDraft, declaredTypes: [PasteboardType], generation: Int) -> String? {
        guard store.clearGeneration == generation else { return "the history was cleared" }
        let settings = settings()
        let decision = CapturePolicy(settings: settings).decision(types: declaredTypes, sourceBundleID: draft.sourceBundleID)
        if case .ignore(let reason) = decision { return String(describing: reason) }
        switch draft.kind {
        case .image where !settings.captureImages: return "images are no longer kept"
        case .file where !settings.captureFiles: return "files are no longer kept"
        default: return nil
        }
    }
}
