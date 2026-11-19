import AppKit
import UniformTypeIdentifiers

/// The live dialogs, as sheets on the Settings window (or app-modal when
/// it isn't there).
@MainActor
final class SettingsDialogs: SettingsDialogPresenting {
    /// The Settings window, which the sheets attach to.
    weak var window: NSWindow?

    /// An open panel in /Applications for app bundles. The sandbox's
    /// user-selected read-only entitlement lets Kept read the chosen apps'
    /// Info.plist for their bundle IDs.
    func chooseApplications() async -> [URL] {
        let panel = NSOpenPanel()
        panel.message = "Choose apps whose copies Kept should never save."
        panel.prompt = "Exclude"
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false

        let response: NSApplication.ModalResponse
        if let window {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }
        return response == .OK ? panel.urls : []
    }

    func confirmClearHistory(_ prompt: ClearHistoryPrompt) async -> ClearHistoryChoice? {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = prompt.message
        alert.informativeText = prompt.detail
        for action in prompt.actions {
            let button = alert.addButton(withTitle: action.title)
            button.hasDestructiveAction = action.isDestructive
        }

        let response: NSApplication.ModalResponse
        if let window {
            response = await alert.beginSheetModal(for: window)
        } else {
            response = alert.runModal()
        }
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard prompt.actions.indices.contains(index) else { return nil }
        return prompt.actions[index].choice
    }
}
