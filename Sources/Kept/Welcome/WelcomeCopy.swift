/// The welcome window's words: where Kept is, how to open it, and the one
/// permission it will ask for. Plain statements, no marketing.
enum WelcomeCopy {
    static let windowTitle = "Welcome to Kept"
    static let title = "Kept is in your menu bar"
    static let pasting = "Pasting into other apps needs your permission. Kept asks for it the first time you paste."

    /// How to open the panel, with the shortcut as recorded ("⇧⌘V"), or
    /// the icon alone when there's no shortcut.
    static func openLine(shortcut: String?) -> String {
        guard let shortcut, !shortcut.isEmpty else {
            return "Click Kept's icon in the menu bar to see what you've copied. You can set a shortcut in Settings."
        }
        return "Press \(shortcut) in any app, or click Kept's icon in the menu bar, to see what you've copied."
    }
}
