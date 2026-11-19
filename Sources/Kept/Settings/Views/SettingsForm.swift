import SwiftUI

/// A settings pane's rows, stacked and centered in the window's fixed width.
struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.SettingsLayout.rowSpacing) {
            content
        }
        .padding(.vertical, Theme.SettingsLayout.verticalPadding)
        .frame(width: Theme.SettingsLayout.width)
    }
}
