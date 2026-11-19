import SwiftUI

/// A short explanation under a control: small, secondary, wrapping. Under a
/// checkbox it's indented to line up with the checkbox's title.
struct SettingsNote: View {
    let text: String
    var underCheckbox = false

    var body: some View {
        Text(text)
            .font(Theme.SettingsLayout.note)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, underCheckbox ? Theme.SettingsLayout.checkboxIndent : 0)
    }
}
