import KeptCore
import SwiftUI

/// Startup, history size, how pasting works, and where the panel opens.
struct GeneralPane: View {
    let model: SettingsModel

    private static let labelWidth: CGFloat = 120

    var body: some View {
        @Bindable var model = model
        @Bindable var preferences = model.preferences
        let launchAtLogin = model.launchAtLogin
        SettingsForm {
            SettingsRow(label: "Startup:", labelWidth: Self.labelWidth) {
                Toggle("Open Kept at login", isOn: $model.isLaunchAtLoginOn)
                if let note = launchAtLogin.note {
                    SettingsNote(text: note, underCheckbox: true)
                }
                if launchAtLogin.offersLoginItemsSettings {
                    Button("Open Login Items…") { model.openLoginItemsSettings() }
                        .padding(.leading, Theme.SettingsLayout.checkboxIndent)
                }
            }

            SettingsRow(label: "History size:", labelWidth: Self.labelWidth) {
                Picker("History size", selection: $preferences.historyLimit) {
                    ForEach(model.historyLimitChoices, id: \.self) { limit in
                        Text(ClearHistoryPrompt.clips(limit)).tag(limit)
                    }
                }
                .labelsHidden()
                .fixedSize()
                SettingsNote(text: "Your newest clips stay. Lowering this deletes the oldest ones right away; pinned clips don't count and always stay.")
            }

            SettingsRow(label: "Pasting:", labelWidth: Self.labelWidth) {
                Toggle("Paste into the active app", isOn: $preferences.pasteDirectly)
                SettingsNote(text: pasteNote, underCheckbox: true)
                if model.pasteStatus == .needsPermission {
                    Button("Open Privacy & Security…") { model.requestPasteAccess() }
                        .padding(.leading, Theme.SettingsLayout.checkboxIndent)
                }
                Toggle("Always paste as plain text", isOn: $preferences.alwaysPastePlainText)
                    .padding(.top, Theme.SettingsLayout.controlSpacing)
                SettingsNote(
                    text: "Leaves out fonts, colors and links. ⌥⏎ pastes with formatting instead.",
                    underCheckbox: true
                )
            }

            SettingsRow(label: "Open Kept:", labelWidth: Self.labelWidth) {
                Picker("Open Kept", selection: $preferences.panelPosition) {
                    Text("In the center of the active screen").tag(PanelPosition.activeScreenCenter)
                    Text("At the mouse pointer").tag(PanelPosition.mouse)
                    Text("Below the menu bar icon").tag(PanelPosition.statusItem)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                SettingsNote(text: "Where your shortcut opens it. Clicking the menu bar icon always opens it below the icon.")
            }
        }
    }

    private var pasteNote: String {
        switch model.pasteStatus {
        case .ready:
            "Picking a clip pastes it where you're typing."
        case .needsPermission:
            "Kept needs your permission to paste. Until you allow it, picking a clip copies it and you press ⌘V."
        case .copiesOnly:
            "Picking a clip only copies it; you press ⌘V to paste."
        }
    }
}
