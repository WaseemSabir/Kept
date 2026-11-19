import KeyboardShortcuts
import SwiftUI

/// The global shortcuts, each with a recorder and what it does. Only "Open
/// Kept" has a default (⇧⌘V); the others start empty.
struct ShortcutsPane: View {
    private static let labelWidth: CGFloat = 200
    private static let contentWidth: CGFloat = 300

    var body: some View {
        SettingsForm {
            row(
                "Open Kept:",
                .togglePanel,
                note: "Opens and closes your clipboard history from any app. If ⇧⌘V clashes with an app's Paste and Match Style, try ⌃⌘V."
            )
            row(
                "Paste clipboard as plain text:",
                .pastePlainText,
                note: "Pastes what you copied last without its fonts, colors and links."
            )
            row(
                "Pause or resume capture:",
                .togglePause,
                note: "Stops saving what you copy, or starts again. The menu bar icon turns hollow while capture is paused."
            )
            SettingsNote(text: "Shortcuts work in every app. Include ⌘ or ⌃, so they don't type a character.")
                .padding(.leading, Self.labelWidth + Theme.SettingsLayout.labelGap)
                .frame(width: Self.labelWidth + Theme.SettingsLayout.labelGap + Self.contentWidth, alignment: .leading)
        }
    }

    private func row(_ label: String, _ name: KeyboardShortcuts.Name, note: String) -> some View {
        SettingsRow(label: label, labelWidth: Self.labelWidth, contentWidth: Self.contentWidth) {
            KeyboardShortcuts.Recorder(for: name)
                .fixedSize()
                // The recorder is an AppKit field without a text baseline
                // SwiftUI can see; line its text up with the label.
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            SettingsNote(text: note)
        }
    }
}
