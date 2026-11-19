import SwiftUI

/// A key cap and what it does: "⌘P Pin".
struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            KeyCap(keys: keys)
            Text(label)
                .font(Theme.Typography.footerKey)
                .foregroundStyle(Theme.Colors.inkMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(keys)")
    }
}
