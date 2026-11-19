import SwiftUI

/// The copy-only hint's content: "Copied. Press ⌘V to paste." and, the
/// first time Kept couldn't paste, why and a button to allow it.
///
/// Drawn on the hint window's vibrancy (or an opaque card in snapshots),
/// inside a hairline that follows the window's rounded corners.
struct PasteHintView: View {
    let hint: PastePlan.Hint
    let permissionDetail: String
    var onAllow: @MainActor () -> Void = {}
    var onHover: @MainActor (Bool) -> Void = { _ in }

    var body: some View {
        content
            .padding(Theme.Layout.hintPadding)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Layout.hintCornerRadius, style: .continuous)
                    .strokeBorder(Theme.Colors.hairline, lineWidth: 0.5)
            }
            .onHover { onHover($0) }
    }

    @ViewBuilder
    private var content: some View {
        switch hint {
        case .pressCommandV:
            title
        case .allowPasting:
            VStack(alignment: .leading, spacing: 6) {
                title
                Text(permissionDetail)
                    .font(Theme.Typography.hintDetail)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer(minLength: 0)
                    Button(PasteHintCopy.allowButton) { onAllow() }
                        .controlSize(.small)
                        .focusable(false)
                }
                .padding(.top, 4)
            }
            .frame(width: Theme.Layout.hintWidth - 2 * Theme.Layout.hintPadding, alignment: .leading)
        }
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(PasteHintCopy.titleBeforeKeys)
            KeyCap(keys: PasteHintCopy.keys)
            Text(PasteHintCopy.titleAfterKeys)
        }
        .font(Theme.Typography.hintTitle)
        .foregroundStyle(Theme.Colors.ink)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PasteHintCopy.spokenTitle)
    }
}
