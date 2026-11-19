import KeptCore
import SwiftUI

/// The big search field, always focused, with the type filter tokens at its
/// end. The query starts at the same x as the list's text.
struct SearchBar: View {
    @Bindable var model: PanelViewModel
    @FocusState private var isFocused: Bool
    @Environment(\.isStaticRendering) private var isStaticRendering

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.searchGlyph)
                .foregroundStyle(Theme.Colors.inkMuted)
                .frame(width: Theme.Layout.leadingColumnWidth, alignment: .leading)
                .accessibilityHidden(true)
            field
                .frame(maxWidth: .infinity, alignment: .leading)
            FilterTokens(selection: $model.filter)
                .padding(.leading, Theme.Spacing.gutter)
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .frame(height: Theme.Layout.searchBarHeight)
        .onAppear { isFocused = true }
        .onChange(of: model.presentationCount) { isFocused = true }
    }

    @ViewBuilder
    private var field: some View {
        if isStaticRendering {
            Text(model.query.isEmpty ? "Search" : model.query)
                .font(Theme.Typography.searchField)
                .foregroundStyle(model.query.isEmpty ? Theme.Colors.inkFaint : Theme.Colors.ink)
                .lineLimit(1)
        } else {
            TextField("Search", text: $model.query)
                .textFieldStyle(.plain)
                .font(Theme.Typography.searchField)
                .foregroundStyle(Theme.Colors.ink)
                .focused($isFocused)
                .focusEffectDisabled()
                .accessibilityLabel("Search clips")
        }
    }
}

/// Compact, quiet filter names; the active one is marked with the highlighter.
private struct FilterTokens: View {
    @Binding var selection: ClipFilter

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ClipFilter.allCases, id: \.self) { filter in
                let isActive = filter == selection
                Button {
                    selection = filter
                } label: {
                    Text(ClipDisplay.title(for: filter))
                        .font(Theme.Typography.filterToken)
                        .foregroundStyle(isActive ? AnyShapeStyle(Theme.Colors.markerInk) : AnyShapeStyle(Theme.Colors.inkMuted))
                        .marked(isActive, height: Theme.Layout.tokenMarkerHeight, leading: 4, trailing: 4)
                        .padding(.horizontal, 6)
                        .frame(height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show")
    }
}
