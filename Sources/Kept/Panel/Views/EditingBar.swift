import SwiftUI

/// Replaces the footer while a name or text is edited: what saves and what
/// cancels (clickable too), and on the right a notice or, while renaming,
/// what an empty name does. Esc cancels the edit here, never the panel.
struct EditingBar: View {
    let model: PanelViewModel

    var body: some View {
        let isRenaming = model.keyMode == .renaming
        HStack(spacing: 14) {
            Button {
                model.commitEditing()
            } label: {
                KeyHint(keys: isRenaming ? "⏎" : "⌘S", label: isRenaming ? "Rename" : "Save")
            }
            .buttonStyle(.plain)
            .focusable(false)
            Button {
                model.cancelEditing()
            } label: {
                KeyHint(keys: "esc", label: "Cancel")
            }
            .buttonStyle(.plain)
            .focusable(false)
            Spacer(minLength: Theme.Spacing.gutter)
            if let notice = model.notice {
                Text(notice)
                    .font(Theme.Typography.footerKey)
                    .foregroundStyle(Theme.Colors.ink)
                    .lineLimit(1)
            } else if isRenaming {
                Text("Leave it empty to remove the name.")
                    .font(Theme.Typography.footerKey)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .frame(height: Theme.Layout.footerHeight)
    }
}
