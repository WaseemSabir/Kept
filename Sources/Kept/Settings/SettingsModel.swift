import AppKit
import KeptCore
import KeyboardShortcuts
import Observation
import UniformTypeIdentifiers

/// What the Settings panes show and do. Most controls bind straight to
/// `Preferences`; this adds what needs the system (the login item, the
/// paste permission, dialogs) or the history, behind protocols so tests can
/// play every case.
@MainActor
@Observable
final class SettingsModel {
    /// What "Paste into the active app" does right now.
    enum PasteStatus: Equatable, Sendable {
        /// The setting is off: picking a clip copies it.
        case copiesOnly
        /// Kept can post ⌘V.
        case ready
        /// The setting is on but Kept lacks the PostEvent permission, so it
        /// copies and shows a hint instead.
        case needsPermission
    }

    let preferences: Preferences
    let about: AboutInfo
    @ObservationIgnored let appIcon: NSImage

    private(set) var loginItemStatus: LoginItemStatus
    private(set) var loginItemFailure: LaunchAtLoginState.Failure?
    private(set) var canPostEvents: Bool
    /// Whether macOS lets Kept read the clipboard (macOS 15.4+).
    private(set) var pasteboardAccess: PasteboardAccess
    /// "Show Kept in the menu bar"; ⌘-dragging the icon away turns it off.
    private(set) var showsMenuBarIcon: Bool
    /// Something that went wrong clearing the history, shown under the button.
    private(set) var historyNotice: String?

    /// Opens the welcome window (About's button).
    @ObservationIgnored var onShowWelcome: @MainActor () -> Void = {}
    /// The recorded shortcut for opening Kept, e.g. "⇧⌘V"; `nil` when
    /// there's none.
    @ObservationIgnored var openShortcut: @MainActor () -> String? = {
        KeyboardShortcuts.getShortcut(for: .togglePanel)?.description
    }
    /// The macOS major version, for copy that names System Settings panes.
    @ObservationIgnored var osMajorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

    @ObservationIgnored private let store: HistoryStore?
    @ObservationIgnored private let loginItem: any LoginItemControlling
    @ObservationIgnored private let permission: any PermissionChecking
    @ObservationIgnored private let onboarding: PasteOnboarding
    @ObservationIgnored private let dialogs: any SettingsDialogPresenting
    @ObservationIgnored private let icons: IconCache
    @ObservationIgnored private let pasteboard: any PasteboardAccessChecking
    @ObservationIgnored private let menuBarIcon: MenuBarIconPreference

    init(
        preferences: Preferences,
        store: HistoryStore?,
        loginItem: any LoginItemControlling,
        permission: any PermissionChecking,
        onboarding: PasteOnboarding,
        dialogs: any SettingsDialogPresenting,
        icons: IconCache,
        about: AboutInfo,
        appIcon: NSImage,
        pasteboard: any PasteboardAccessChecking = SystemPasteboardAccess(),
        menuBarIcon: MenuBarIconPreference = MenuBarIconPreference()
    ) {
        self.preferences = preferences
        self.store = store
        self.loginItem = loginItem
        self.permission = permission
        self.onboarding = onboarding
        self.dialogs = dialogs
        self.icons = icons
        self.about = about
        self.appIcon = appIcon
        self.pasteboard = pasteboard
        self.menuBarIcon = menuBarIcon
        loginItemStatus = loginItem.status
        canPostEvents = permission.canPostEvents
        pasteboardAccess = pasteboard.access
        showsMenuBarIcon = menuBarIcon.isShown
    }

    /// Reads the login item, the paste permission, clipboard access and the
    /// menu bar icon again: the user can change them all outside Settings.
    func refresh() {
        loginItemStatus = loginItem.status
        canPostEvents = permission.canPostEvents
        pasteboardAccess = pasteboard.access
        showsMenuBarIcon = menuBarIcon.isShown
    }

    // MARK: General

    var launchAtLogin: LaunchAtLoginState {
        LaunchAtLoginState(status: loginItemStatus, failure: loginItemFailure)
    }

    /// The "Open Kept at login" checkbox.
    var isLaunchAtLoginOn: Bool {
        get { launchAtLogin.isOn }
        set { setLaunchAtLogin(newValue) }
    }

    /// Registers or unregisters the login item, then reads its status back;
    /// a failure is kept for the note under the checkbox.
    func setLaunchAtLogin(_ isOn: Bool) {
        loginItemFailure = nil
        do {
            if isOn {
                try loginItem.register()
            } else {
                try loginItem.unregister()
            }
        } catch {
            loginItemFailure = isOn ? .couldNotRegister : .couldNotUnregister
            Log.settings.error("Couldn't change the login item: \(String(describing: error), privacy: .public)")
        }
        loginItemStatus = loginItem.status
    }

    func openLoginItemsSettings() {
        loginItem.openSystemSettings()
    }

    /// The "Show Kept in the menu bar" checkbox. The menu bar item follows
    /// the preference as soon as it changes.
    var isMenuBarIconShown: Bool {
        get { showsMenuBarIcon }
        set {
            menuBarIcon.isShown = newValue
            showsMenuBarIcon = newValue
        }
    }

    /// Under the checkbox: how to get back to Kept without the icon.
    var menuBarIconNote: String {
        let reopen = "Opening Kept again from Applications brings the icon back."
        guard let shortcut = openShortcut() else {
            return "Without the icon, open Kept from Applications. \(reopen)"
        }
        return "Without the icon, \(shortcut) still opens Kept. \(reopen)"
    }

    // MARK: Clipboard access

    /// What's wrong with clipboard access and where to fix it, or `nil`.
    var pasteboardAccessNote: (problem: String, direction: String)? {
        guard let problem = pasteboardAccess.problem,
              let direction = pasteboardAccess.direction(osMajorVersion: osMajorVersion)
        else { return nil }
        return (problem, direction)
    }

    func openPasteboardAccessSettings() {
        pasteboard.openSettings()
    }

    var pasteStatus: PasteStatus {
        guard preferences.pasteDirectly else { return .copiesOnly }
        return canPostEvents ? .ready : .needsPermission
    }

    /// "Open Privacy & Security…": the first time, asks macOS, which adds
    /// Kept to the list and shows its own prompt with a way to System
    /// Settings; after that, opens the pane.
    func requestPasteAccess() {
        if onboarding.hasRequestedAccess {
            permission.openSettings()
        } else {
            onboarding.hasRequestedAccess = true
            permission.requestAccess()
        }
    }

    /// The history sizes to offer, including the current one.
    var historyLimitChoices: [Int] {
        PreferenceDefaults.historyLimitChoices(including: preferences.historyLimit)
    }

    // MARK: Excluded apps

    var excludedApps: [ExcludedApp] {
        preferences.excludedBundleIDs.map { ExcludedApp(bundleID: $0, name: icons.appName(for: $0)) }
    }

    /// The app's icon, or the generic one when it isn't installed.
    func icon(for app: ExcludedApp) -> NSImage {
        icons.appIcon(for: app.bundleID) ?? NSWorkspace.shared.icon(for: .applicationBundle)
    }

    /// "+": asks for apps and excludes them.
    func chooseAppsToExclude() async {
        let urls = await dialogs.chooseApplications()
        exclude(appsAt: urls)
    }

    /// Excludes the apps at `urls`, skipping anything without a bundle ID
    /// and apps already on the list. Returns the bundle IDs added.
    @discardableResult
    func exclude(appsAt urls: [URL]) -> [String] {
        var added: [String] = []
        for url in urls {
            guard let bundleID = ExcludedApp.bundleIdentifier(ofAppAt: url) else {
                Log.settings.error("No bundle ID in \(url.path, privacy: .public)")
                continue
            }
            if preferences.excludeApp(bundleID) { added.append(bundleID) }
        }
        return added
    }

    /// "−".
    func removeExcludedApps(_ bundleIDs: Set<String>) {
        preferences.removeExcludedApps(bundleIDs)
    }

    func restoreDefaultExcludedApps() {
        preferences.restoreDefaultExcludedApps()
    }

    var canRestoreDefaultExcludedApps: Bool {
        !preferences.excludedAppsAreDefault
    }

    // MARK: History

    /// "13 clips in your history, 2 of them pinned."
    var historySummary: String {
        guard let store else { return "Kept couldn't open your history." }
        let total = store.pinned.count + store.recent.count
        guard total > 0 else { return "Your history is empty." }
        let clips = ClearHistoryPrompt.clips(total)
        guard !store.pinned.isEmpty else { return "\(clips) in your history." }
        return "\(clips) in your history, \(store.pinned.count.formatted()) of them pinned."
    }

    /// The choices of "Forget unpinned clips", in order.
    var forgetAfterChoices: [RetentionPeriod] { RetentionPeriod.allCases }

    /// A choice's name in the menu: "Never", "After a week"…
    static func title(for period: RetentionPeriod) -> String {
        switch period {
        case .never: "Never"
        case .day: "After a day"
        case .week: "After a week"
        case .month: "After a month"
        }
    }

    /// Under "Forget unpinned clips": what the choice means.
    var forgetAfterNote: String {
        switch preferences.forgetAfter {
        case .never: "Unpinned clips stay until your history is full."
        case .day, .week, .month: "Counted from a clip's last copy or paste. Pinned clips stay."
        }
    }

    /// The confirmation "Clear history…" would show; `nil` when there's
    /// nothing to clear.
    var clearHistoryPrompt: ClearHistoryPrompt? {
        guard let store else { return nil }
        return ClearHistoryPrompt(unpinnedCount: store.recent.count, pinnedCount: store.pinned.count)
    }

    /// "Clear history…": asks, then clears what the user chose.
    func clearHistory() async {
        guard let store, let prompt = clearHistoryPrompt else { return }
        guard let choice = await dialogs.confirmClearHistory(prompt) else { return }
        historyNotice = nil
        do {
            switch choice {
            case .unpinned: try store.clearUnpinned()
            case .everything: try store.clearAll()
            }
        } catch {
            historyNotice = "Kept couldn't clear the history. Try again, or quit and reopen Kept."
            Log.history.error("Couldn't clear the history: \(String(describing: error), privacy: .public)")
        }
    }

    /// A quiet note for About when the history had trouble at launch.
    var historyHealthNote: String? {
        guard let store else {
            return "Kept couldn't open your history, so it isn't saving what you copy."
        }
        let skipped = store.skippedRecordCount
        if skipped == 1 {
            return "1 clip in your history couldn't be read, so Kept left it out."
        }
        if skipped > 1 {
            return "\(skipped.formatted()) clips in your history couldn't be read, so Kept left them out."
        }
        if !store.openWarnings.isEmpty {
            return "Kept couldn't tidy up your history at launch. It tries again next time."
        }
        return nil
    }
}
