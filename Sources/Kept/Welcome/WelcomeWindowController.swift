import AppKit
import SwiftUI

/// Owns the welcome window: shown by itself once, at the first launch
/// (`WelcomeState`), and again from About.
///
/// Like Settings it activates Kept, and closing it hands the keyboard back
/// to the app the user was in. "Open Kept" waits for that hand-off before
/// opening the panel, so the panel's first paste goes to that app rather
/// than finding Kept in front.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    private let settings: SettingsModel
    private let activeApps: ActiveAppTracker
    private let state: WelcomeState
    private let openPanel: @MainActor () -> Void
    private var window: SettingsWindow?
    private var hostingController: NSHostingController<WelcomeView>?
    private var handOffObserver: (any NSObjectProtocol)?

    /// How long "Open Kept" waits for another app to become active.
    private static let handOffTimeout: Duration = .milliseconds(600)

    init(
        settings: SettingsModel,
        activeApps: ActiveAppTracker,
        state: WelcomeState = WelcomeState(),
        openPanel: @escaping @MainActor () -> Void
    ) {
        self.settings = settings
        self.activeApps = activeApps
        self.state = state
        self.openPanel = openPanel
        super.init()
    }

    /// Shows the window if Kept has never shown it.
    func showOnFirstLaunch() {
        guard state.shouldShowAtLaunch else { return }
        show()
    }

    func show() {
        state.hasBeenShown = true
        settings.refresh()
        let window = window ?? makeWindow()
        // The shortcut may have been changed since the window was made.
        hostingController?.rootView = makeView()
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        Log.settings.notice("Showing the welcome window")
    }

    private func makeView() -> WelcomeView {
        WelcomeView(
            settings: settings,
            shortcut: settings.openShortcut(),
            onOpenKept: { [weak self] in self?.openKept() },
            onDone: { [weak self] in self?.window?.close() }
        )
    }

    private func makeWindow() -> SettingsWindow {
        let controller = NSHostingController(rootView: makeView())
        controller.sizingOptions = [.preferredContentSize]
        let window = SettingsWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = WelcomeCopy.windowTitle
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self
        window.setContentSize(controller.view.fittingSize)
        window.center()
        self.window = window
        hostingController = controller
        return window
    }

    // MARK: Open Kept

    /// Closes the window, which hands activation back, then opens the panel
    /// once Kept is no longer active (or after a moment, if nothing took
    /// over).
    private func openKept() {
        window?.close()
        guard NSApplication.shared.isActive else {
            openPanel()
            return
        }
        handOffObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.finishOpeningKept()
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: Self.handOffTimeout)
            self?.finishOpeningKept()
        }
    }

    private func finishOpeningKept() {
        guard let observer = handOffObserver else { return }
        NotificationCenter.default.removeObserver(observer)
        handOffObserver = nil
        openPanel()
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        // Back from System Settings: the login item or clipboard access may
        // have changed.
        settings.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        activeApps.returnFocus(closing: window)
    }
}
