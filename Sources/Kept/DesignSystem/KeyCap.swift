import SwiftUI

/// A small key cap, e.g. ⌘P, for shortcut hints.
struct KeyCap: View {
    let keys: String

    var body: some View {
        Text(keys)
            .font(Theme.Typography.keyCap)
            .foregroundStyle(Theme.Colors.inkMuted)
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 16)
            .background(Theme.Colors.wash, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Theme.Colors.hairline, lineWidth: 0.5)
            }
    }
}
