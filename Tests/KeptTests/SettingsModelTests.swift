import AppKit
import ServiceManagement
import Testing
@testable import Kept
import KeptCore

@MainActor
@Suite("Settings model")
struct SettingsModelTests {
    /// A Settings model over throwaway preferences and a temporary history,
    /// with the login item, permission and dialogs faked.
    @MainActor
    private final class Harness {
        let directory: URL
        let suiteName: String
        let preferences: Preferences
        let onboarding: PasteOnboarding
        let store: HistoryStore
        let loginItem: FakeLoginItem
        let permission: FakePermission
        let dialogs: FakeDialogs
        let pasteboard: FakePasteboardAccess
        let menuBarIcon: MenuBarIconPreference
        let model: SettingsModel

        init(texts: [String] = ["one", "two", "three"]) throws {
            let directory = try makeTemporaryDirectory()
            let suiteName = "app.kept.tests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            let preferences = Preferences(defaults: defaults)
            let onboarding = PasteOnboarding(defaults: defaults)
            let store = try makeStore(in: directory, texts: texts)
            let loginItem = FakeLoginItem()
            let permission = FakePermission()
            let dialogs = FakeDialogs()
            let pasteboard = FakePasteboardAccess()
            let menuBarIcon = MenuBarIconPreference(defaults: defaults)
            self.directory = directory
            self.suiteName = suiteName
            self.preferences = preferences
            self.onboarding = onboarding
            self.store = store
            self.loginItem = loginItem
            self.permission = permission
            self.dialogs = dialogs
            self.pasteboard = pasteboard
            self.menuBarIcon = menuBarIcon
            model = SettingsModel(
                preferences: preferences,
                store: store,
                loginItem: loginItem,
                permission: permission,
                onboarding: onboarding,
                dialogs: dialogs,
                icons: IconCache(),
                about: AboutInfo(version: "1.2.3", build: "45"),
                appIcon: NSImage(),
                pasteboard: pasteboard,
                menuBarIcon: menuBarIcon
            )
        }

        func tearDown() {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
            removeTemporaryDirectory(directory)
        }
    }

    // MARK: Launch at login

    @Test("SMAppService statuses map one to one")
    func serviceStatuses() {
        #expect(LoginItemStatus(SMAppService.Status.enabled) == .enabled)
        #expect(LoginItemStatus(SMAppService.Status.requiresApproval) == .requiresApproval)
        #expect(LoginItemStatus(SMAppService.Status.notRegistered) == .notRegistered)
        #expect(LoginItemStatus(SMAppService.Status.notFound) == .notFound)
    }

    @Test("The checkbox follows the status, and asks for approval when macOS wants it")
    func launchAtLoginStates() {
        let enabled = LaunchAtLoginState(status: .enabled, failure: nil)
        #expect(enabled.isOn && enabled.note == nil && !enabled.offersLoginItemsSettings)

        let pending = LaunchAtLoginState(status: .requiresApproval, failure: nil)
        #expect(pending.isOn)
        #expect(pending.note == "Allow Kept in Login Items settings to finish turning this on.")
        #expect(pending.offersLoginItemsSettings)

        for status in [LoginItemStatus.notRegistered, .notFound] {
            let off = LaunchAtLoginState(status: status, failure: nil)
            #expect(!off.isOn && off.note == nil && !off.offersLoginItemsSettings)
        }

        let failed = LaunchAtLoginState(status: .notFound, failure: .couldNotRegister)
        #expect(!failed.isOn)
        #expect(failed.note?.contains("Developer ID") == true)
        #expect(failed.offersLoginItemsSettings)

        let stuck = LaunchAtLoginState(status: .enabled, failure: .couldNotUnregister)
        #expect(stuck.isOn)
        #expect(stuck.note?.contains("remove it in Login Items settings") == true)
        #expect(stuck.offersLoginItemsSettings)
    }

    @Test("Turning launch at login on and off registers, reads back and explains failures")
    func launchAtLogin() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let model = harness.model
        #expect(!model.isLaunchAtLoginOn)

        model.isLaunchAtLoginOn = true
        #expect(harness.loginItem.registrations == 1)
        #expect(model.isLaunchAtLoginOn)
        #expect(model.launchAtLogin.note == nil)

        model.isLaunchAtLoginOn = false
        #expect(harness.loginItem.unregistrations == 1)
        #expect(!model.isLaunchAtLoginOn)

        harness.loginItem.failure = TestSetupError(description: "Operation not permitted")
        model.isLaunchAtLoginOn = true
        #expect(!model.isLaunchAtLoginOn)
        #expect(model.loginItemFailure == .couldNotRegister)
        #expect(model.launchAtLogin.offersLoginItemsSettings)
        model.openLoginItemsSettings()
        #expect(harness.loginItem.settingsOpened == 1)

        // Trying again clears the old failure.
        harness.loginItem.failure = nil
        model.isLaunchAtLoginOn = true
        #expect(model.loginItemFailure == nil)
        #expect(model.isLaunchAtLoginOn)
    }

    @Test("Changes made in System Settings show up on refresh")
    func refresh() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let model = harness.model

        harness.loginItem.status = .requiresApproval
        harness.permission.canPostEvents = false
        #expect(model.loginItemStatus == .notRegistered)
        #expect(model.pasteStatus == .ready)

        model.refresh()
        #expect(model.loginItemStatus == .requiresApproval)
        #expect(model.isLaunchAtLoginOn)
        #expect(model.pasteStatus == .needsPermission)
    }

    // MARK: Pasting

    @Test("The paste line follows the setting and the permission")
    func pasteStatus() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let model = harness.model
        #expect(model.pasteStatus == .ready)

        harness.permission.canPostEvents = false
        model.refresh()
        #expect(model.pasteStatus == .needsPermission)

        harness.preferences.pasteDirectly = false
        #expect(model.pasteStatus == .copiesOnly)
    }

    @Test("Asking for paste access prompts once, then opens Privacy & Security")
    func requestPasteAccess() throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        harness.model.requestPasteAccess()
        #expect(harness.permission.requests == 1)
        #expect(harness.permission.settingsOpened == 0)
        #expect(harness.onboarding.hasRequestedAccess)

        harness.model.requestPasteAccess()
        #expect(harness.permission.requests == 1)
        #expect(harness.permission.settingsOpened == 1)
    }

    @Test("History sizes include the one in effect")
    func historyLimitChoices() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        #expect(harness.model.historyLimitChoices == PreferenceDefaults.historyLimitChoices)

        harness.preferences.historyLimit = 1_200
        #expect(harness.model.historyLimitChoices.contains(1_200))
        #expect(harness.model.historyLimitChoices == harness.model.historyLimitChoices.sorted())
    }

    // MARK: Excluded apps

    @Test("Adds apps by bundle ID, once, skipping anything without one")
    func excludesApps() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let vault = try makeAppBundle(named: "Vault", bundleID: "com.example.Vault", in: harness.directory)
        let notes = try makeAppBundle(named: "Notes", bundleID: "org.example.Notes", in: harness.directory)
        let broken = harness.directory.appendingPathComponent("Broken.app", isDirectory: true)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)

        let added = harness.model.exclude(appsAt: [vault, broken, notes, vault])
        #expect(added == ["com.example.Vault", "org.example.Notes"])
        #expect(Array(harness.preferences.excludedBundleIDs.suffix(2)) == ["com.example.Vault", "org.example.Notes"])
        #expect(harness.model.excludedApps.map(\.bundleID) == harness.preferences.excludedBundleIDs)
        #expect(harness.model.canRestoreDefaultExcludedApps)
        #expect(harness.preferences.captureSettings.excludes(bundleID: "com.example.vault"))
    }

    @Test("The add button excludes what the dialog returns")
    func choosesApps() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let vault = try makeAppBundle(named: "Vault", bundleID: "com.example.Vault", in: harness.directory)
        harness.dialogs.chosenApps = [vault]

        await harness.model.chooseAppsToExclude()
        #expect(harness.preferences.isExcluded("com.example.Vault"))

        harness.dialogs.chosenApps = []
        await harness.model.chooseAppsToExclude()
        #expect(harness.preferences.excludedBundleIDs.count == PreferenceDefaults.excludedBundleIDs.count + 1)
    }

    @Test("Removes the selected apps and restores the defaults")
    func removesAndRestores() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let model = harness.model
        #expect(!model.canRestoreDefaultExcludedApps)

        model.removeExcludedApps(["com.apple.Passwords", "com.bitwarden.desktop"])
        #expect(!harness.preferences.isExcluded("com.apple.Passwords"))
        #expect(model.excludedApps.count == PreferenceDefaults.excludedBundleIDs.count - 2)
        #expect(model.canRestoreDefaultExcludedApps)

        model.restoreDefaultExcludedApps()
        #expect(harness.preferences.excludedBundleIDs == PreferenceDefaults.excludedBundleIDs)
        #expect(!model.canRestoreDefaultExcludedApps)
    }

    @Test("Rows name missing password managers by name, and other missing apps by bundle ID")
    func excludedAppRows() {
        let missing = ExcludedApp(bundleID: "com.example.Gone", name: nil)
        #expect(missing.title == "com.example.Gone")
        #expect(!missing.isInstalled)
        let present = ExcludedApp(bundleID: "com.apple.Passwords", name: "Passwords")
        #expect(present.title == "Passwords")
        #expect(present.isInstalled)

        let known = [
            "com.1password.1password": "1Password",
            "com.agilebits.onepassword7": "1Password 7",
            "com.bitwarden.desktop": "Bitwarden",
            "org.keepassxc.keepassxc": "KeePassXC",
            "com.apple.Passwords": "Passwords",
            "com.apple.keychainaccess": "Keychain Access",
        ]
        for (bundleID, name) in known {
            let row = ExcludedApp(bundleID: bundleID, name: nil)
            #expect(row.title == name)
            #expect(!row.isInstalled)
        }
        // Every default has a name, and case doesn't matter.
        for bundleID in PreferenceDefaults.excludedBundleIDs {
            #expect(ExcludedApp.knownName(for: bundleID) != nil, "\(bundleID)")
        }
        #expect(ExcludedApp.knownName(for: "ORG.KEEPASSXC.KEEPASSXC") == "KeePassXC")
        // The installed app's own name wins.
        #expect(ExcludedApp(bundleID: "com.1password.1password", name: "1Password 8").title == "1Password 8")
    }

    // MARK: Menu bar icon

    @Test("The menu bar checkbox writes the preference the menu bar item follows")
    func menuBarIcon() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let model = harness.model
        #expect(model.isMenuBarIconShown)
        #expect(harness.menuBarIcon.isShown)

        model.isMenuBarIconShown = false
        #expect(!harness.menuBarIcon.isShown)
        #expect(!model.isMenuBarIconShown)

        // ⌘-dragging the icon away (or opening Kept again) shows up on refresh.
        harness.menuBarIcon.isShown = true
        #expect(!model.isMenuBarIconShown)
        model.refresh()
        #expect(model.isMenuBarIconShown)
    }

    @Test("The menu bar note names the recorded shortcut, if any")
    func menuBarIconNote() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let model = harness.model
        model.openShortcut = { "⌃⌘V" }
        #expect(model.menuBarIconNote == "Without the icon, ⌃⌘V still opens Kept. Opening Kept again from Applications brings the icon back.")
        model.openShortcut = { nil }
        #expect(model.menuBarIconNote == "Without the icon, open Kept from Applications. Opening Kept again from Applications brings the icon back.")
    }

    // MARK: Clipboard access

    @Test("Clipboard access trouble shows with where to fix it, and refreshes")
    func pasteboardAccess() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let model = harness.model
        model.osMajorVersion = 26
        #expect(model.pasteboardAccessNote == nil)

        harness.pasteboard.access = .denied
        #expect(model.pasteboardAccessNote == nil)
        model.refresh()
        let note = try #require(model.pasteboardAccessNote)
        #expect(note.problem == "Kept can't see what you copy until you allow it.")
        #expect(note.direction.contains("Paste from Other Apps"))

        model.openPasteboardAccessSettings()
        #expect(harness.pasteboard.settingsOpened == 1)

        harness.pasteboard.access = .allowed
        model.refresh()
        #expect(model.pasteboardAccessNote == nil)
    }

    // MARK: Forgetting old clips

    @Test("Forget unpinned clips offers four choices and says what each means")
    func forgetAfterChoices() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let model = harness.model
        #expect(model.forgetAfterChoices == [.never, .day, .week, .month])
        #expect(model.forgetAfterNote == "Unpinned clips stay until your history is full.")
        harness.preferences.forgetAfter = .week
        #expect(model.forgetAfterNote == "Counted from a clip's last copy or paste. Pinned clips stay.")
        #expect(SettingsModel.title(for: .week) == "After a week")
    }

    // MARK: Clearing the history

    @Test("The clear prompt fits what's in the history")
    func clearPrompts() throws {
        #expect(ClearHistoryPrompt(unpinnedCount: 0, pinnedCount: 0) == nil)

        let both = try #require(ClearHistoryPrompt(unpinnedCount: 12, pinnedCount: 1))
        #expect(both.message == "Clear your clipboard history?")
        #expect(both.detail == "This deletes 12 clips. Pinned clips stay unless you choose Clear everything. You can't undo this.")
        #expect(both.actions.map(\.title) == ["Clear history", "Clear everything", "Cancel"])
        #expect(both.actions.map(\.choice) == [.unpinned, .everything, nil])
        #expect(both.actions.map(\.isDestructive) == [false, true, false])

        let unpinned = try #require(ClearHistoryPrompt(unpinnedCount: 1, pinnedCount: 0))
        #expect(unpinned.detail == "This deletes 1 clip. You can't undo this.")
        #expect(unpinned.actions.map(\.choice) == [.unpinned, nil])

        let pinned = try #require(ClearHistoryPrompt(unpinnedCount: 0, pinnedCount: 2))
        #expect(pinned.message == "Clear your pinned clips?")
        #expect(pinned.detail == "Only pinned clips are left. This deletes 2 pinned clips. You can't undo this.")
        #expect(pinned.actions.map(\.title) == ["Clear pinned clips", "Cancel"])
        #expect(pinned.actions.map(\.choice) == [.everything, nil])
    }

    @Test("Clearing asks first, and keeps pins unless told otherwise")
    func clearsHistory() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let model = harness.model
        let store = harness.store
        let one = try #require(store.recent.first { $0.title == "one" })
        try store.pin(one.id)
        #expect(model.historySummary == "3 clips in your history, 1 of them pinned.")

        harness.dialogs.answer = nil
        await model.clearHistory()
        #expect(store.recent.count == 2)

        harness.dialogs.answer = .unpinned
        await model.clearHistory()
        #expect(store.recent.isEmpty)
        #expect(store.pinned.map(\.title) == ["one"])
        #expect(model.historySummary == "1 clip in your history, 1 of them pinned.")

        harness.dialogs.answer = .everything
        await model.clearHistory()
        #expect(store.pinned.isEmpty)
        #expect(model.historySummary == "Your history is empty.")
        #expect(model.clearHistoryPrompt == nil)
        #expect(model.historyNotice == nil)

        // Nothing left to ask about.
        await model.clearHistory()
        #expect(harness.dialogs.prompts.map(\.actions.count) == [3, 3, 2])
    }

    // MARK: About

    @Test("About reads the version and build from the bundle")
    func about() throws {
        #expect(AboutInfo(version: "0.2.0", build: "142").versionLine == "Version 0.2.0 (142)")
        #expect(AboutInfo(version: "0.2.0", build: "0.2.0").versionLine == "Version 0.2.0")
        #expect(AboutInfo(version: "0.2.0", build: nil).versionLine == "Version 0.2.0")
        #expect(AboutInfo(version: nil, build: "3").versionLine == "Development build")

        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let app = try makeAppBundle(named: "Kept", bundleID: "app.kept.Test", version: "1.4.0", build: "77", in: directory)
        let bundle = try #require(Bundle(url: app))
        #expect(AboutInfo(bundle: bundle) == AboutInfo(version: "1.4.0", build: "77"))
    }

    @Test("About stays quiet about a healthy history and speaks up without one")
    func historyHealth() throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        #expect(harness.model.historyHealthNote == nil)

        let withoutHistory = SettingsModel(
            preferences: harness.preferences,
            store: nil,
            loginItem: harness.loginItem,
            permission: harness.permission,
            onboarding: harness.onboarding,
            dialogs: harness.dialogs,
            icons: IconCache(),
            about: AboutInfo(version: nil, build: nil),
            appIcon: NSImage()
        )
        #expect(withoutHistory.historyHealthNote == "Kept couldn't open your history, so it isn't saving what you copy.")
        #expect(withoutHistory.historySummary == "Kept couldn't open your history.")
        #expect(withoutHistory.clearHistoryPrompt == nil)
    }
}

// MARK: Fakes

@MainActor
private final class FakeLoginItem: LoginItemControlling {
    var status = LoginItemStatus.notRegistered
    /// Thrown by `register` and `unregister` when set.
    var failure: (any Error)?
    private(set) var registrations = 0
    private(set) var unregistrations = 0
    private(set) var settingsOpened = 0

    func register() throws {
        if let failure { throw failure }
        registrations += 1
        status = .enabled
    }

    func unregister() throws {
        if let failure { throw failure }
        unregistrations += 1
        status = .notRegistered
    }

    func openSystemSettings() {
        settingsOpened += 1
    }
}

@MainActor
private final class FakePermission: PermissionChecking {
    var canPostEvents = true
    private(set) var requests = 0
    private(set) var settingsOpened = 0

    func requestAccess() { requests += 1 }
    func openSettings() { settingsOpened += 1 }
}

@MainActor
final class FakePasteboardAccess: PasteboardAccessChecking {
    var access = PasteboardAccess.allowed
    private(set) var settingsOpened = 0

    func openSettings() { settingsOpened += 1 }
}

@MainActor
private final class FakeDialogs: SettingsDialogPresenting {
    var chosenApps: [URL] = []
    var answer: ClearHistoryChoice?
    private(set) var prompts: [ClearHistoryPrompt] = []

    func chooseApplications() async -> [URL] {
        chosenApps
    }

    func confirmClearHistory(_ prompt: ClearHistoryPrompt) async -> ClearHistoryChoice? {
        prompts.append(prompt)
        return answer
    }
}
