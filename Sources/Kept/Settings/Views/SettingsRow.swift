import SwiftUI

/// One row of a settings pane: a right-aligned label beside its controls,
/// lined up on the first line of text, in the classic Mac layout.
struct SettingsRow<Content: View>: View {
    let label: String
    /// The same for every row of a pane, so the controls line up.
    let labelWidth: CGFloat
    var contentWidth: CGFloat = Theme.SettingsLayout.contentWidth
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.SettingsLayout.labelGap) {
            Text(label)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .trailing)
            VStack(alignment: .leading, spacing: Theme.SettingsLayout.controlSpacing) {
                content
            }
            .frame(width: contentWidth, alignment: .leading)
        }
    }
}
