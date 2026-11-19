import AppKit

/// Remembers the last app other than Kept that became active, so closing a
/// Kept window can give the keyboard back to it (`FocusReturn`): the app
/// the user was in last, not the one in front when the window opened, and
/// right even when relaunching Kept activated it first.
///
/// Lives as long as the app.
@MainActor
final class ActiveAppTracker {
    private(set) var lastOtherApp: NSRunningApplication?
    private var observer: (any NSObjectProtocol)?
    private let ownProcessID = ProcessInfo.processInfo.processIdentifier

    init(workspace: NSWorkspace = .shared) {
        note(workspace.frontmostApplication)
        observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                self?.note(app)
            }
        }
    }

    /// Hands the keyboard back as `window` closes: to the last other app,
    /// or by hiding Kept when there's none. Nothing changes while another
    /// Kept window (Settings, the welcome window) stays open.
    func returnFocus(closing window: NSWindow) {
        let application = NSApplication.shared
        let otherWindowIsOpen = application.windows.contains { other in
            other !== window && other.isVisible && other.styleMask.contains(.titled) && !(other is NSPanel)
        }
        let app = lastOtherApp.flatMap { $0.isTerminated ? nil : $0 }
        switch FocusReturn.choice(
            isKeptActive: application.isActive,
            otherWindowIsOpen: otherWindowIsOpen,
            lastOtherApp: app?.processIdentifier
        ) {
        case .stay:
            break
        case .activate:
            guard let app else { return }
            application.yieldActivation(to: app)
            _ = app.activate(options: [])
        case .hide:
            application.hide(nil)
        }
    }

    private func note(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ownProcessID else { return }
        lastOtherApp = app
    }
}
