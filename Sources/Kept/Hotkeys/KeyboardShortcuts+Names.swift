import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Opens or closes the panel. ⇧⌘V is the shortcut other clipboard managers
    /// (Flycut, Clipy, Paste) use; users can change it in Settings.
    static let togglePanel = Self("togglePanel", initial: Shortcut(.v, modifiers: [.shift, .command]))
}
