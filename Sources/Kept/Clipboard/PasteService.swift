import AppKit
import KeptCore

/// Puts clips back on the pasteboard.
///
/// For now that's copy only: the user pastes with ⌘V. Synthesizing ⌘V into
/// the previous app (with the PostEvent permission) is the next step.
@MainActor
final class PasteService: ClipCopying {
    enum Failure: Error, CustomStringConvertible {
        /// The pasteboard refused the write.
        case pasteboardRejected

        var description: String {
            switch self {
            case .pasteboardRejected: "The pasteboard didn't accept the clip."
            }
        }
    }

    private let store: HistoryStore
    private let writer: PasteboardWriter
    private let monitor: PasteboardMonitor

    init(store: HistoryStore, writer: PasteboardWriter, monitor: PasteboardMonitor) {
        self.store = store
        self.writer = writer
        self.monitor = monitor
    }

    func copy(_ clip: Clip, asPlainText: Bool) throws {
        let items = try store.representations(for: clip.id)
        let payload = PasteboardWriter.payload(of: items, plainTextOnly: asPlainText)
        guard let changeCount = writer.write(payload, sourceBundleID: clip.sourceBundleID) else {
            throw Failure.pasteboardRejected
        }
        monitor.noteOwnWrite(changeCount: changeCount)
        try store.markUsed(clip.id)
    }
}
