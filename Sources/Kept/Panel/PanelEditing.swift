import Foundation

/// What the panel is editing: a clip's name, in its row, or its text, in
/// the preview. The drafts themselves live in `PanelViewModel`.
enum PanelEditing: Equatable, Sendable {
    /// The text being edited and how to show it.
    struct TextEdit: Equatable, Sendable {
        let clipID: UUID
        /// The text as the editor first showed it, so saving it unchanged
        /// changes nothing.
        let original: String
        /// Rich text: saving keeps the text and drops the formatting.
        let dropsFormatting: Bool
        /// Set in SF Mono, as the preview sets it.
        let isCode: Bool
    }

    case name(clipID: UUID)
    case text(TextEdit)

    var clipID: UUID {
        switch self {
        case .name(let id): id
        case .text(let edit): edit.clipID
        }
    }

    var keyMode: PanelKeyMode {
        switch self {
        case .name: .renaming
        case .text: .editingText
        }
    }
}
