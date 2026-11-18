import SwiftUI

/// The panel's content: a large search field over the clip list.
///
/// For now the list is always empty; history arrives with the store (M1)
/// and capture (M2), and the view model with the full panel (M3).
struct PanelView: View {
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
            Divider()
            emptyState
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { isSearchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.searchField)
                .foregroundStyle(Theme.Colors.inkMuted)
                .frame(width: Theme.Layout.leadingColumnWidth, alignment: .leading)
                .accessibilityHidden(true)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(Theme.Typography.searchField)
                .foregroundStyle(Theme.Colors.ink)
                .focused($isSearchFocused)
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .frame(height: Theme.Layout.searchBarHeight)
    }

    /// Sits where the first row will be, its text on the same x as the query.
    private var emptyState: some View {
        Text("Copy something and it shows up here.")
            .font(Theme.Typography.rowTitle)
            .foregroundStyle(Theme.Colors.inkMuted)
            .padding(.leading, Theme.Spacing.gutter + Theme.Layout.leadingColumnWidth)
            .frame(height: Theme.Layout.rowHeight)
    }
}
