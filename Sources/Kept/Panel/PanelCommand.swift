/// Something the user asked the panel to do, usually with a key.
enum PanelCommand: Equatable, Sendable {
    /// ↑ / ↓, ⌃P / ⌃N: one row up (negative) or down.
    case moveSelection(by: Int)
    /// PgUp / PgDn: a page up (negative) or down.
    case movePage(by: Int)
    /// ⌘↑, Home.
    case selectFirst
    /// ⌘↓, End.
    case selectLast
    /// ⏎ (and ⌥⏎ for plain text): put the selected clip back and close.
    case activate(plainText: Bool)
    /// ⌘⏎: copy the selected clip without pasting, and close.
    case copyOnly
    /// ⌘1–⌘9 (and ⌥⌘1–⌥⌘9 for plain text): act on row N, counted from 0.
    case activateRow(Int, plainText: Bool)
    /// ⌘P.
    case togglePin
    /// ⌘⌫.
    case delete
    /// ⌥⌘⌫: ask to clear every unpinned clip.
    case requestClearUnpinned
    /// ⌃U.
    case clearQuery
    /// Esc: dismiss a confirmation, clear the search, or close the panel.
    case cancel
    /// Tab / ⇧Tab.
    case nextFilter
    case previousFilter
    /// ⌘X, ⌘C, ⌘V, ⌘A, ⌘Z, ⇧⌘Z in the search field. Kept has no Edit menu
    /// (it's an agent app), so the panel sends these actions itself.
    case edit(TextEditAction)
}

/// A standard text editing action for the search field.
enum TextEditAction: Equatable, Sendable {
    case cut
    case copy
    case paste
    case selectAll
    case undo
    case redo
}
