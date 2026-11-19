/// The copy-only hint's words.
///
/// Up to macOS 26 the PostEvent permission is listed under Privacy &
/// Security › Accessibility, so the hint names it. macOS 27 renamed that
/// pane ("Device Control and Data Access") and 27.3 splits it again, and
/// which part lists PostEvent isn't confirmed (docs/RESEARCH.md §5), so
/// there the hint names only Privacy & Security, which is right either way.
enum PasteHintCopy {
    static let title = "Copied. Press ⌘V to paste."
    static let titleBeforeKeys = "Copied. Press"
    static let keys = "⌘V"
    static let titleAfterKeys = "to paste."
    /// Read by VoiceOver for the title, which draws ⌘V as a key cap.
    static let spokenTitle = "Copied. Press Command V to paste."
    static let allowButton = "Allow Kept to paste…"

    /// Why Kept didn't paste, for the first hint.
    static func permissionDetail(osMajorVersion: Int) -> String {
        if osMajorVersion >= 27 {
            "To paste for you, Kept needs your permission in Privacy & Security settings."
        } else {
            "To paste for you, Kept needs Accessibility access in Privacy & Security settings."
        }
    }
}
