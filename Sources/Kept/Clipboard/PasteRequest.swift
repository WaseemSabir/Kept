/// What the user asked for when putting something back.
enum PasteRequest: Equatable, Sendable {
    /// ⏎, ⌘1–⌘9 and a double-click (`alternate: false`); ⌥⏎ and ⌥⌘1–⌥⌘9
    /// (`alternate: true`), which flip the format: plain text, or with
    /// formatting when "always paste plain text" is on.
    case paste(alternate: Bool)
    /// ⌘⏎: write the clip as ⏎ would, but never post ⌘V.
    case copyOnly
    /// The global "paste clipboard as plain text" shortcut: whatever is on
    /// the pasteboard now, as plain text.
    case clipboardAsPlainText
}
