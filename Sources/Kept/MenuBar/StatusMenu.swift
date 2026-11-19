import AppKit
import KeyboardShortcuts

/// The menu bar icon's menu (right-click, ⌃-click or ⌥-click):
///
///     Open Kept           ⇧⌘V
///     ───────────────────
///     Pause capture
///     Ignore next copy
///     Clear history…
///     ───────────────────
///     Settings…           ⌘,
///     ───────────────────
///     Quit Kept           ⌘Q
///
/// "Open Kept" and "Pause capture" show their global shortcuts (whatever is
/// recorded in Settings, kept up to date by KeyboardShortcuts). `update`
/// refreshes titles and states each time the menu opens.
@MainActor
final class StatusMenu: NSObject {
    /// What the items do.
    struct Actions {
        var openPanel: @MainActor () -> Void = {}
        var togglePause: @MainActor () -> Void = {}
        var ignoreNextCopy: @MainActor () -> Void = {}
        var clearHistory: @MainActor () -> Void = {}
        var openSettings: @MainActor () -> Void = {}
        var quit: @MainActor () -> Void = { NSApplication.shared.terminate(nil) }
    }

    let menu = NSMenu()
    let openItem = NSMenuItem(title: "Open Kept", action: nil, keyEquivalent: "")
    let pauseItem = NSMenuItem(title: "Pause capture", action: nil, keyEquivalent: "")
    let ignoreNextCopyItem = NSMenuItem(title: "Ignore next copy", action: nil, keyEquivalent: "")
    let clearHistoryItem = NSMenuItem(title: "Clear history…", action: nil, keyEquivalent: "")
    let settingsItem = NSMenuItem(title: "Settings…", action: nil, keyEquivalent: ",")
    let quitItem = NSMenuItem(title: "Quit Kept", action: nil, keyEquivalent: "q")

    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
        super.init()
        menu.autoenablesItems = false

        connect(openItem, #selector(openChosen(_:)))
        openItem.setShortcut(for: .togglePanel)
        connect(pauseItem, #selector(pauseChosen(_:)))
        pauseItem.setShortcut(for: .togglePause)
        connect(ignoreNextCopyItem, #selector(ignoreNextCopyChosen(_:)))
        ignoreNextCopyItem.toolTip = "Kept won't save the next thing you copy."
        connect(clearHistoryItem, #selector(clearHistoryChosen(_:)))
        connect(settingsItem, #selector(settingsChosen(_:)))
        connect(quitItem, #selector(quitChosen(_:)))

        menu.items = [
            openItem,
            .separator(),
            pauseItem,
            ignoreNextCopyItem,
            clearHistoryItem,
            .separator(),
            settingsItem,
            .separator(),
            quitItem,
        ]
        update(StatusMenuState())
    }

    /// Brings titles, checkmarks and availability up to date.
    func update(_ state: StatusMenuState) {
        pauseItem.title = state.pauseTitle
        ignoreNextCopyItem.isEnabled = state.canIgnoreNextCopy
        ignoreNextCopyItem.state = state.isIgnoreNextCopyChecked ? .on : .off
        clearHistoryItem.isEnabled = state.canClearHistory
    }

    private func connect(_ item: NSMenuItem, _ action: Selector) {
        item.target = self
        item.action = action
    }

    @objc private func openChosen(_ sender: NSMenuItem) { actions.openPanel() }
    @objc private func pauseChosen(_ sender: NSMenuItem) { actions.togglePause() }
    @objc private func ignoreNextCopyChosen(_ sender: NSMenuItem) { actions.ignoreNextCopy() }
    @objc private func clearHistoryChosen(_ sender: NSMenuItem) { actions.clearHistory() }
    @objc private func settingsChosen(_ sender: NSMenuItem) { actions.openSettings() }
    @objc private func quitChosen(_ sender: NSMenuItem) { actions.quit() }
}
