import Foundation

/// The dialogs Settings asks AppKit for. `SettingsModel` depends on this
/// rather than on `NSOpenPanel` and `NSAlert`, so tests can answer them.
@MainActor
protocol SettingsDialogPresenting: AnyObject {
    /// Asks which apps to exclude; the chosen app bundles, or none.
    func chooseApplications() async -> [URL]
    /// Asks before clearing the history; `nil` when the user cancels.
    func confirmClearHistory(_ prompt: ClearHistoryPrompt) async -> ClearHistoryChoice?
}
