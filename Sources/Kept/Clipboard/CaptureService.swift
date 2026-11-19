import AppKit
import KeptCore

/// Turns pasteboard changes into history: reads the pasteboard (policy
/// first), builds the clip off the main actor, and records it.
///
/// Builds run side by side, so a slow one (a huge image) never holds up
/// the copies after it. Each clip is recorded with the time its copy was
/// seen, and the store orders clips by that time, so builds may finish in
/// any order.
@MainActor
final class CaptureService {
    private let pasteboard: NSPasteboard
    private let store: HistoryStore
    private let settings: @MainActor () -> CaptureSettings
    private let reader = PasteboardReader()
    private var builds: [Int: Task<Void, Never>] = [:]
    private var nextBuildID = 0

    init(
        pasteboard: NSPasteboard = .general,
        store: HistoryStore,
        settings: @escaping @MainActor () -> CaptureSettings
    ) {
        self.pasteboard = pasteboard
        self.store = store
        self.settings = settings
    }

    /// Reads what's on the pasteboard now and records it unless it's ignored.
    func captureCurrentContents() {
        let settings = settings()
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let copiedAt = Date()

        switch reader.read(from: pasteboard, settings: settings, frontmostBundleID: frontmost) {
        case .ignored(let reason):
            Log.capture.debug("Skipped a copy: \(String(describing: reason), privacy: .public)")

        case .changedDuringRead:
            Log.capture.debug("The pasteboard changed while it was read; the next poll takes the new copy.")

        case .snapshot(let snapshot):
            let builder = ClipBuilder(settings: settings, imageInspector: ImageIOInspector())
            let id = nextBuildID
            nextBuildID += 1
            builds[id] = Task { [weak self] in
                let draft = await Task.detached(priority: .userInitiated) {
                    builder.build(from: PasteboardReader.normalized(snapshot))
                }.value
                self?.finishBuild(id, draft: draft, copiedAt: copiedAt)
            }
        }
    }

    /// Waits for every build started so far (for tests).
    func waitUntilIdle() async {
        for build in Array(builds.values) {
            await build.value
        }
    }

    private func finishBuild(_ id: Int, draft: ClipDraft?, copiedAt: Date) {
        builds[id] = nil
        guard let draft else { return }
        // A slow build can finish after the same content was copied again
        // and recorded; recording it now would move that clip back in time.
        let existing = store.pinned.first { $0.contentHash == draft.contentHash }
            ?? store.recent.first { $0.contentHash == draft.contentHash }
        if let existing, existing.lastCopiedAt > copiedAt { return }
        do {
            try store.record(draft, at: copiedAt)
        } catch {
            Log.capture.error("Couldn't record a clip: \(String(describing: error), privacy: .public)")
        }
    }
}
