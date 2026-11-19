import SwiftUI

/// What to say when there's nothing to list, set where the first row's
/// text would be.
struct EmptyStateView: View {
    let state: EmptyState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.title)
                .font(Theme.Typography.emptyTitle)
                .foregroundStyle(Theme.Colors.ink)
            if let hint = state.hint {
                Text(hint)
                    .font(Theme.Typography.emptyHint)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, Theme.Spacing.gutter + Theme.Layout.leadingColumnWidth)
        .padding(.trailing, Theme.Spacing.gutter)
        .padding(.top, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}
