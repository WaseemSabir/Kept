import AppKit

/// Owns the Settings window: an ordinary titled window (made on first use)
/// whose toolbar switches panes.
///
/// Showing it activates Kept, since Settings takes the keyboard like any
/// window. Closing it hands focus back to the app that was active before,
/// so Kept never lingers as an invisible active app.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    /// The last pane shown, in UserDefaults. `-settingsPane shortcuts` on
    /// the command line opens a given pane (CI's smoke test uses it).
    static let selectedPaneKey = "settingsPane"

    private let model: SettingsModel
    private let dialogs: SettingsDialogs
    private let defaults: UserDefaults
    private var window: SettingsWindow?
    private var tabController: SettingsTabViewController?
    /// The app that was active before Settings opened.
    private var previousApp: NSRunningApplication?

    init(model: SettingsModel, dialogs: SettingsDialogs, defaults: UserDefaults = .standard) {
        self.model = model
        self.dialogs = dialogs
        self.defaults = defaults
        super.init()
    }

    var isVisible: Bool { window?.isVisible ?? false }

    /// Shows Settings (on `pane`, or the last pane shown) and activates Kept.
    func show(pane: SettingsPane? = nil) {
        rememberPreviousApp()
        let window = prepareWindow(pane: pane)
        model.refresh()
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        let paneName = tabController?.selectedPane.rawValue ?? "none"
        Log.settings.notice("Showing Settings: \(paneName, privacy: .public)")
    }

    /// Makes the window (the first time) and selects `pane`, without
    /// showing it. Snapshots render it this way.
    @discardableResult
    func prepareWindow(pane: SettingsPane? = nil) -> SettingsWindow {
        let window = window ?? makeWindow()
        if let pane { tabController?.selectedPane = pane }
        tabController?.fitWindowToSelectedPane(animated: false)
        return window
    }

    private func makeWindow() -> SettingsWindow {
        let tabController = SettingsTabViewController(model: model)
        if let stored = defaults.string(forKey: Self.selectedPaneKey), let pane = SettingsPane(rawValue: stored) {
            tabController.selectedPane = pane
        }
        tabController.onSelectPane = { [weak self] pane in
            guard let self else { return }
            defaults.set(pane.rawValue, forKey: Self.selectedPaneKey)
        }

        let window = SettingsWindow(contentViewController: tabController)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        // Open on the Space the user is on, not where Settings was last.
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self
        // A sensible size until the pane reports its own.
        window.setContentSize(NSSize(width: Theme.SettingsLayout.width, height: 420))
        tabController.fitWindowToSelectedPane(animated: false)
        window.center()

        dialogs.window = window
        self.window = window
        self.tabController = tabController
        return window
    }

    /// Notes the app the user was in, unless Kept is already active (then
    /// the earlier note stands).
    private func rememberPreviousApp() {
        guard !NSApplication.shared.isActive,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        previousApp = app
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        // Back from System Settings: the login item or permission may have
        // changed.
        model.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        let previousApp = previousApp
        self.previousApp = nil
        guard NSApplication.shared.isActive, let previousApp, !previousApp.isTerminated else { return }
        NSApplication.shared.yieldActivation(to: previousApp)
        _ = previousApp.activate(options: [])
    }
}
