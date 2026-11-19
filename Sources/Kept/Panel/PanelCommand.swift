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
    /// ⏎: paste the selected clip and close. ⌥⏎ (`alternate`) pastes it
    /// in the other format: plain text, or with formatting when "always
    /// paste plain text" is on.
    case activate(alternate: Bool)
    /// ⌘⏎: copy the selected clip without pasting, and close.
    case copyOnly
    /// ⌘1–⌘9 (⌥⌘1–⌥⌘9 for the other format): paste row N, counted from 0.
    case activateRow(Int, alternate: Bool)
    /// ⌘P.
    case togglePin
    /// ⌥⌘↑ / ⌥⌘↓: move the selected pin up (negative) or down in the
    /// pinned section.
    case movePin(by: Int)
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
    /// ⌘,: open Settings.
    case openSettings
    /// ⌘X, ⌘C, ⌘V, ⌘A, ⌘Z, ⇧⌘Z in the search field. Kept has no Edit menu
    /// (it's an agent app), so the panel sends these actions itself.
    case edit(TextEditAction)
}

extension PanelCommand {
    /// The paste the command asks for; `nil` for every other command.
    var pasteRequest: PasteRequest? {
        switch self {
        case .activate(let alternate), .activateRow(_, let alternate): .paste(alternate: alternate)
        case .copyOnly: .copyOnly
        default: nil
        }
    }
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
