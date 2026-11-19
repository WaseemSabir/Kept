import SwiftUI

/// Key hints for what the keys do right now; on the right, a problem to
/// report or that capture is paused.
struct PanelFooter: View {
    let model: PanelViewModel

    var body: some View {
        HStack(spacing: 14) {
            // Hints only for what the keys can do right now.
            if model.selectedClip != nil {
                KeyHint(keys: "⏎", label: model.primaryActionTitle)
                KeyHint(keys: "⌥⏎", label: model.alternateActionTitle)
                if let copyOnlyTitle = model.copyOnlyActionTitle {
                    KeyHint(keys: "⌘⏎", label: copyOnlyTitle)
                }
                KeyHint(keys: "⌘P", label: model.pinActionTitle)
                KeyHint(keys: "⌘⌫", label: "Delete")
            } else if model.isSearching {
                KeyHint(keys: "esc", label: "Clear search")
            } else {
                KeyHint(keys: "esc", label: "Close")
            }
            Spacer(minLength: Theme.Spacing.gutter)
            if let notice = model.notice {
                Text(notice)
                    .font(Theme.Typography.footerKey)
                    .foregroundStyle(Theme.Colors.ink)
                    .lineLimit(1)
            } else if model.isCapturePaused {
                PausedIndicator()
            }
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .frame(height: Theme.Layout.footerHeight)
    }
}

/// The menu bar glyph's hollow marker and "Capture paused".
private struct PausedIndicator: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(nsImage: MenuBarIcon.image(paused: true))
                .renderingMode(.template)
                .resizable()
                .frame(width: 15, height: 13.5)
                .accessibilityHidden(true)
            Text("Capture paused")
                .font(Theme.Typography.footerKey)
        }
        .foregroundStyle(Theme.Colors.inkMuted)
    }
}

/// Replaces the footer while asking to clear the history. Inline rather
/// than an alert, which would activate Kept and pull focus from the app the
/// user is working in.
struct ClearConfirmationBar: View {
    let model: PanelViewModel

    var body: some View {
        HStack(spacing: 14) {
            Text(message)
                .font(Theme.Typography.footerKey)
                .foregroundStyle(Theme.Colors.ink)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.gutter)
            Button {
                model.confirmClearUnpinned()
            } label: {
                KeyHint(keys: "⏎", label: "Clear history")
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

    private var message: String {
        let count = model.unpinnedCount
        let clips = count == 1 ? "1 unpinned clip" : "\(count.formatted()) unpinned clips"
        return "Clear \(clips)? Pinned clips stay."
    }
}
