/// What the menu bar menu shows right now: the titles and which items are
/// on or available. A value, so the menu's logic is tested without AppKit.
struct StatusMenuState: Equatable, Sendable {
    /// `Preferences.isPaused`.
    var isPaused = false
    /// "Ignore next copy" is armed and waiting for a copy.
    var isIgnoringNextCopy = false
    /// The history opened; without it there is nothing to clear.
    var isHistoryAvailable = true

    /// The pause item names what choosing it does.
    var pauseTitle: String {
        isPaused ? "Resume capture" : "Pause capture"
    }

    /// While paused nothing is captured, so there's no next copy to ignore.
    var canIgnoreNextCopy: Bool {
        !isPaused && isHistoryAvailable
    }

    /// Checked while armed.
    var isIgnoreNextCopyChecked: Bool {
        isIgnoringNextCopy && canIgnoreNextCopy
    }

    var canClearHistory: Bool {
        isHistoryAvailable
    }
}
