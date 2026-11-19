import AppKit
import KeyboardShortcuts

/// Kept's menu bar item. A click toggles the panel; a right click (or a
/// Control- or Option-click) opens `StatusMenu`.
///
/// The menu is attached only while it opens (`performClick`, not replaying
/// the mouse event, which stopped working on macOS 27): with a menu
/// attached, every click would open the menu instead of the panel.
///
/// The icon can be ⌘-dragged out of the menu bar. That and the Settings
/// checkbox meet in `MenuBarIconPreference`, which the item follows both
/// ways, so the icon can always be brought back.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let statusMenu: StatusMenu
    private let togglePanel: @MainActor () -> Void
    private let menuState: @MainActor () -> StatusMenuState
    private let iconPreference: MenuBarIconPreference
    private var visibilityObservation: NSKeyValueObservation?
    private var defaultsObserver: (any NSObjectProtocol)?

    /// - Parameters:
    ///   - togglePanel: a plain click.
    ///   - menuActions: what the menu's items do.
    ///   - menuState: read each time the menu opens.
    ///   - iconPreference: whether the icon shows.
    init(
        togglePanel: @escaping @MainActor () -> Void,
        menuActions: StatusMenu.Actions,
        menuState: @escaping @MainActor () -> StatusMenuState,
        iconPreference: MenuBarIconPreference = MenuBarIconPreference()
    ) {
        self.togglePanel = togglePanel
        self.menuState = menuState
        self.iconPreference = iconPreference
        statusMenu = StatusMenu(actions: menuActions)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusMenu.menu.delegate = self
        configureButton()
        followIconPreference()
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
        let event = NSApplication.shared.currentEvent
        if Self.wantsMenu(event?.type, modifiers: event?.modifierFlags ?? []) {
            showMenu()
        } else {
            togglePanel()
        }
    }

    /// A right click, or a click with ⌃ or ⌥ held, opens the menu; any
    /// other click (⌘ and ⇧ included) toggles the panel.
    static func wantsMenu(_ eventType: NSEvent.EventType?, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard let eventType else { return false }
        return eventType == .rightMouseUp
            || !modifiers.isDisjoint(with: [.control, .option])
    }

    // MARK: Showing the icon

    /// Applies the preference now and keeps the two in step: ⌘-dragging the
    /// icon away turns the preference off, and the Settings checkbox (or
    /// opening Kept again) shows or hides the icon.
    private func followIconPreference() {
        applyIconPreference()
        visibilityObservation = statusItem.observe(\.isVisible) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.iconVisibilityDidChange()
            }
        }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: iconPreference.defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyIconPreference()
            }
        }
    }

    private func applyIconPreference() {
        let isShown = iconPreference.isShown
        if statusItem.isVisible != isShown { statusItem.isVisible = isShown }
    }

    private func iconVisibilityDidChange() {
        let isVisible = statusItem.isVisible
        if iconPreference.isShown != isVisible { iconPreference.isShown = isVisible }
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
