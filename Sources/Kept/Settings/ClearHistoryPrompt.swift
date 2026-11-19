import Foundation

/// The confirmation for "Clear history…" in Settings: the question, what
/// it deletes, and the buttons, worked out from what's in the history.
///
/// The first action is the default (⏎); the last, "Cancel", answers Esc.
/// Keeping pins is the default whenever there are pins to keep.
struct ClearHistoryPrompt: Equatable, Sendable {
    struct Action: Equatable, Sendable {
        let title: String
        /// `nil` for Cancel.
        let choice: ClearHistoryChoice?
        var isDestructive = false
    }

    let message: String
    let detail: String
    let actions: [Action]

    /// `nil` when the history is empty: there's nothing to ask about.
    init?(unpinnedCount: Int, pinnedCount: Int) {
        let cancel = Action(title: "Cancel", choice: nil)
        switch (unpinnedCount > 0, pinnedCount > 0) {
        case (true, true):
            message = "Clear your clipboard history?"
            detail = "This deletes \(Self.clips(unpinnedCount)). Pinned clips stay unless you choose Clear everything. You can't undo this."
            actions = [
                Action(title: "Clear history", choice: .unpinned),
                Action(title: "Clear everything", choice: .everything, isDestructive: true),
                cancel,
            ]
        case (true, false):
            message = "Clear your clipboard history?"
            detail = "This deletes \(Self.clips(unpinnedCount)). You can't undo this."
            actions = [Action(title: "Clear history", choice: .unpinned, isDestructive: true), cancel]
        case (false, true):
            message = "Clear your pinned clips?"
            detail = "Only pinned clips are left. This deletes \(Self.clips(pinnedCount, pinned: true)). You can't undo this."
            actions = [Action(title: "Clear pinned clips", choice: .everything, isDestructive: true), cancel]
        case (false, false):
            return nil
        }
    }

    /// "1 clip", "1,204 clips", "2 pinned clips".
    static func clips(_ count: Int, pinned: Bool = false) -> String {
        let noun = pinned ? "pinned clip" : "clip"
        return count == 1 ? "1 \(noun)" : "\(count.formatted()) \(noun)s"
    }
}
