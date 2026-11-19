import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?
    private var welcomeController: WelcomeWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment()
        environment.start()
        self.environment = environment

        // The welcome window opens once, at the first launch; About's
        // button opens it again.
        let settings = environment.settingsController
        let welcome = WelcomeWindowController(
            settings: settings.model,
            activeApps: settings.activeApps,
            openPanel: { [weak environment] in environment?.panelController.show() }
        )
        settings.model.onShowWelcome = { [weak welcome] in welcome?.show() }
        welcomeController = welcome
        welcome.showOnFirstLaunch()
    }

    /// Launching Kept again while it's running brings the menu bar icon back
    /// (⌘-dragging removes it, and the Settings checkbox hides it) and opens
    /// Settings: the way back in, also when macOS hides the icon (System
    /// Settings › Menu Bar can, and no API tells an app).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MenuBarIconPreference().isShown = true
        environment?.showSettings()
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
