import AppKit
import KeyboardShortcuts

/// Kept's menu bar item. A click toggles the panel; a right click (or a
/// Control- or Option-click) opens `StatusMenu`.
///
/// The menu is attached only while it opens (`performClick`, not replaying
/// the mouse event, which stopped working on macOS 27): with a menu
/// attached, every click would open the menu instead of the panel.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let statusMenu: StatusMenu
    private let togglePanel: @MainActor () -> Void
    private let menuState: @MainActor () -> StatusMenuState

    /// - Parameters:
    ///   - togglePanel: a plain click.
    ///   - menuActions: what the menu's items do.
    ///   - menuState: read each time the menu opens.
    init(
        togglePanel: @escaping @MainActor () -> Void,
        menuActions: StatusMenu.Actions,
        menuState: @escaping @MainActor () -> StatusMenuState
    ) {
        self.togglePanel = togglePanel
        self.menuState = menuState
        statusMenu = StatusMenu(actions: menuActions)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusMenu.menu.delegate = self
        configureButton()
    }

    /// The icon's frame on screen, for placing the panel below it; `nil`
    /// while it isn't showing (macOS 26 can hide it, and so can the user).
    var buttonFrameOnScreen: CGRect? {
        guard statusItem.isVisible,
              let button = statusItem.button,
              let window = button.window,
              window.isVisible
        else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
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

    /// Shows the hollow marker while capture is paused.
    func setPaused(_ isPaused: Bool) {
        guard let button = statusItem.button else { return }
        button.image = MenuBarIcon.image(paused: isPaused)
        button.toolTip = isPaused ? "Kept: capture paused" : "Kept"
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

    private func showMenu() {
        statusMenu.update(menuState())
        statusItem.menu = statusMenu.menu
        statusItem.button?.performClick(nil)
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        // While a menu tracks, hot keys queue up and fire when it closes;
        // the menu's own key equivalents cover them meanwhile.
        KeyboardShortcuts.isEnabled = false
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
        KeyboardShortcuts.isEnabled = true
    }
}
