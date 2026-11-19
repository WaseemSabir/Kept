import SwiftUI

/// What Kept captures, the apps it never captures from, and clearing the
/// history. When macOS keeps Kept from reading the clipboard (macOS 15.4+),
/// that comes first, with where to change it.
struct PrivacyPane: View {
    let model: SettingsModel

    private static let labelWidth: CGFloat = 120

    var body: some View {
        @Bindable var preferences = model.preferences
        SettingsForm {
            if let note = model.pasteboardAccessNote {
                SettingsRow(label: "Clipboard:", labelWidth: Self.labelWidth) {
                    Text(note.problem)
                        .fontWeight(.medium)
                        .fixedSize(horizontal: false, vertical: true)
                    SettingsNote(text: note.direction)
                    Button("Open Privacy & Security…") { model.openPasteboardAccessSettings() }
                }
            }

            SettingsRow(label: "Capture:", labelWidth: Self.labelWidth) {
                Toggle("Pause capture", isOn: $preferences.isPaused)
                SettingsNote(text: "Kept saves nothing you copy until you turn this off.", underCheckbox: true)
                Toggle("Ignore copies from other devices", isOn: $preferences.ignoreRemoteClipboard)
                    .padding(.top, Theme.SettingsLayout.controlSpacing)
                SettingsNote(
                    text: "Skips what arrives through Universal Clipboard from your iPhone, iPad or other Mac.",
                    underCheckbox: true
                )
                Toggle("Keep images", isOn: $preferences.captureImages)
                    .padding(.top, Theme.SettingsLayout.controlSpacing)
                Toggle("Keep files", isOn: $preferences.captureFiles)
            }

            SettingsRow(label: "Excluded apps:", labelWidth: Self.labelWidth) {
                ExcludedAppsList(model: model)
                SettingsNote(
                    text: "Kept never saves what you copy in these apps. It also skips copies made within a moment of using them. Password managers are on the list from the start."
                )
            }

            SettingsRow(label: "History:", labelWidth: Self.labelWidth) {
                Button("Clear history…") {
                    Task { await model.clearHistory() }
                }
                .disabled(model.clearHistoryPrompt == nil)
                SettingsNote(text: model.historyNotice ?? model.historySummary)
            }
        }
    }
}
