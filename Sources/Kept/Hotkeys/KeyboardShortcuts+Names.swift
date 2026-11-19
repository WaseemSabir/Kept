import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Opens or closes the panel. ⇧⌘V is the shortcut other clipboard managers
    /// (Flycut, Clipy, Paste) use; users can change it in Settings.
    static let togglePanel = Self("togglePanel", initial: Shortcut(.v, modifiers: [.shift, .command]))

    /// Pastes whatever is on the clipboard now as plain text. No default:
    /// ⌥⇧⌘V is the system's "Paste and Match Style", and anything else
    /// might shadow an app's shortcut. Set in Settings.
    static let pastePlainText = Self("pastePlainText")

    /// Pauses or resumes capture (`Preferences.isPaused`). No default.
    static let togglePause = Self("togglePause")
}
