import SwiftUI

/// Replaces the footer while asking to clear the history. Inline rather
/// than an alert, which would activate Kept and pull focus from the app the
/// user is working in. Only ⌥⌘⌫ again (or the button) clears: ⏎ is the
/// paste key, too easily pressed by habit.
struct ClearConfirmationBar: View {
    let model: PanelViewModel

    var body: some View {
        HStack(spacing: 14) {
            Text(model.clearConfirmationMessage)
                .font(Theme.Typography.footerKey)
                .foregroundStyle(Theme.Colors.ink)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.gutter)
            Button {
                model.confirmClearUnpinned()
            } label: {
                KeyHint(keys: "⌥⌘⌫", label: "Clear history")
            }
            .buttonStyle(.plain)
            .focusable(false)
            Button {
                model.cancelClearUnpinned()
            } label: {
                KeyHint(keys: "esc", label: "Cancel")
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .frame(height: Theme.Layout.footerHeight)
    }
}
