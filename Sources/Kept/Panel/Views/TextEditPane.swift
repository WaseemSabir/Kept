import KeptCore
import SwiftUI

/// The preview while a clip's text is edited (⌘E): the text in an editor
/// set as the preview sets it (SF Mono for code, links and colors), on a
/// quiet wash with a hairline edge, its text where the preview's was. For
/// rich text, one quiet line says what saving does. The footer holds Save
/// and Cancel.
struct TextEditPane: View {
    @Bindable var model: PanelViewModel
    let edit: PanelEditing.TextEdit

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Layout.editorCornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            ClipTextEditor(text: $model.textDraft, isCode: edit.isCode) {
                model.textEditorDidResign(for: edit.clipID)
            }
            .background(Theme.Colors.wash, in: shape)
            .overlay { shape.strokeBorder(Theme.Colors.hairline, lineWidth: 0.5) }
            // The editor's own inset puts its text at the pane's.
            .padding(-Theme.Layout.editorInset)
            .padding(.bottom, Theme.Layout.editorInset)
            if edit.dropsFormatting {
                Text("Saving keeps the text and drops the formatting.")
                    .font(Theme.Typography.rowMeta)
                    .foregroundStyle(Theme.Colors.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Theme.Spacing.previewInset)
    }
}
