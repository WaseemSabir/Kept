import SwiftUI

/// The welcome window: where Kept lives, how to open it (the shortcut as
/// recorded), that pasting asks for a permission once, and "Open Kept at
/// login". When macOS keeps Kept from reading the clipboard (15.4+), it says
/// so and where to change it. Native controls, centered, nothing more.
struct WelcomeView: View {
    let settings: SettingsModel
    /// The recorded shortcut for opening Kept, e.g. "⇧⌘V".
    let shortcut: String?
    var onOpenKept: @MainActor () -> Void = {}
    var onDone: @MainActor () -> Void = {}

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 0) {
            Image(nsImage: settings.appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: Theme.WelcomeLayout.iconSize, height: Theme.WelcomeLayout.iconSize)
                .accessibilityHidden(true)
            Text(WelcomeCopy.title)
                .font(Theme.WelcomeLayout.title)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            Text(openLine)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Text(WelcomeCopy.pasting)
                .font(Theme.SettingsLayout.note)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            if let note = settings.pasteboardAccessNote {
                AccessNotice(problem: note.problem, direction: note.direction) {
                    settings.openPasteboardAccessSettings()
                }
                .padding(.top, 16)
            }
            Toggle("Open Kept at login", isOn: $settings.isLaunchAtLoginOn)
                .padding(.top, 18)
            if let note = settings.launchAtLogin.note {
                Text(note)
                    .font(Theme.SettingsLayout.note)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            HStack(spacing: 10) {
                // macOS order: the default button on the right. ⏎ opens
                // Kept; Esc is Done.
                Button {
                    onDone()
                } label: {
                    Text("Done").frame(minWidth: Theme.WelcomeLayout.buttonWidth)
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    onOpenKept()
                } label: {
                    Text("Open Kept").frame(minWidth: Theme.WelcomeLayout.buttonWidth)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.top, 22)
        }
        .multilineTextAlignment(.center)
        .padding(Theme.WelcomeLayout.padding)
        .frame(width: Theme.WelcomeLayout.width)
    }

    /// The open line with the shortcut a weight heavier.
    private var openLine: AttributedString {
        typealias FontAttribute = AttributeScopes.SwiftUIAttributes.FontAttribute
        var line = AttributedString(WelcomeCopy.openLine(shortcut: shortcut))
        if let shortcut, let range = line.range(of: shortcut) {
            line[range][FontAttribute.self] = Font.body.weight(.semibold)
        }
        return line
    }
}

/// Clipboard access trouble: what's wrong, where to fix it, and a button
/// that goes there. A quiet box, no color.
private struct AccessNotice: View {
    let problem: String
    let direction: String
    let openSettings: @MainActor () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        VStack(spacing: 6) {
            Text(problem)
                .fontWeight(.medium)
                .fixedSize(horizontal: false, vertical: true)
            Text(direction)
                .font(Theme.SettingsLayout.note)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Privacy & Security…") { openSettings() }
                .controlSize(.small)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.wash, in: shape)
        .overlay { shape.strokeBorder(Theme.Colors.hairline, lineWidth: 0.5) }
        .accessibilityElement(children: .contain)
    }
}
