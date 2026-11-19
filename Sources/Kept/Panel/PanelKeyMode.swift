/// What the panel's keyboard is doing, which decides how `PanelKeyRouter`
/// reads a key.
enum PanelKeyMode: Equatable, Sendable {
    /// The search field has the keyboard; modified keys act on the list.
    case browsing
    /// A row's name field has the keyboard: ⏎ saves, Esc cancels, and list
    /// shortcuts do nothing.
    case renaming
    /// The preview's text editor has the keyboard: ⌘S or ⌘⏎ save, Esc
    /// cancels, ⏎ and Tab type, and list shortcuts do nothing.
    case editingText
}
