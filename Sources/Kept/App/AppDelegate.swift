import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment()
        environment.start()
        self.environment = environment
    }

    /// Launching Kept again while it's running opens Settings: the way back
    /// in if macOS hides the menu bar icon (System Settings › Menu Bar can,
    /// and no API tells an app).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        environment?.showSettings()
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
