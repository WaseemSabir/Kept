import AppKit
import KeptCore
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
    /// Something that went wrong clearing the history, shown under the button.
    private(set) var historyNotice: String?

    @ObservationIgnored private let store: HistoryStore?
    @ObservationIgnored private let loginItem: any LoginItemControlling
    @ObservationIgnored private let permission: any PermissionChecking
    @ObservationIgnored private let onboarding: PasteOnboarding
    @ObservationIgnored private let dialogs: any SettingsDialogPresenting
    @ObservationIgnored private let icons: IconCache

    init(
        preferences: Preferences,
        store: HistoryStore?,
        loginItem: any LoginItemControlling,
        permission: any PermissionChecking,
        onboarding: PasteOnboarding,
        dialogs: any SettingsDialogPresenting,
        icons: IconCache,
        about: AboutInfo,
        appIcon: NSImage
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
        loginItemStatus = loginItem.status
        canPostEvents = permission.canPostEvents
    }

    /// Reads the login item and the paste permission again: the user can
    /// change both in System Settings while Settings is open.
    func refresh() {
        loginItemStatus = loginItem.status
        canPostEvents = permission.canPostEvents
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
