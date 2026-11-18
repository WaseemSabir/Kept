import AppKit

/// Kept's menu bar item. A click toggles the panel; a right click (or a
/// Control- or Option-click) opens a small menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let togglePanel: @MainActor () -> Void

    init(togglePanel: @escaping @MainActor () -> Void) {
        self.togglePanel = togglePanel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        configureMenu()
    }

    private func configureButton() {
        statusItem.behavior = .removalAllowed
        guard let button = statusItem.button else { return }

        button.image = MenuBarIcon.image(paused: false)
        button.toolTip = "Kept"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureMenu() {
        menu.delegate = self
        menu.autoenablesItems = false

        let settings = NSMenuItem(title: "Settings…", action: nil, keyEquivalent: ",")
        settings.isEnabled = false // The Settings window arrives in M6.
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Kept",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApplication.shared
        menu.addItem(quit)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if Self.wantsMenu(NSApplication.shared.currentEvent) {
            showMenu()
        } else {
            togglePanel()
        }
    }

    private static func wantsMenu(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        return event.type == .rightMouseUp
            || !event.modifierFlags.isDisjoint(with: [.control, .option])
    }

    /// Attaches the menu just long enough to open it; with a menu attached,
    /// every click would open the menu instead of the panel.
    private func showMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }
}
