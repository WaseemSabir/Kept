import Foundation
import Observation
import Testing
@testable import KeptCore

@MainActor
@Suite("Preferences")
struct PreferencesTests {
    let suiteName = "KeptCoreTests.\(UUID().uuidString)"

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: suiteName))
    }

    private func cleanUp() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    @Test("Starts with the documented defaults")
    func startsWithDefaults() throws {
        defer { cleanUp() }
        let preferences = Preferences(defaults: try makeDefaults())
        #expect(preferences.historyLimit == 500)
        #expect(preferences.pasteDirectly == true)
        #expect(preferences.alwaysPastePlainText == false)
        #expect(preferences.panelPosition == .activeScreenCenter)
        #expect(preferences.excludedBundleIDs == [
            "com.apple.Passwords", "com.apple.keychainaccess", "com.1password.1password",
            "com.agilebits.onepassword7", "com.bitwarden.desktop", "org.keepassxc.keepassxc",
        ])
        #expect(preferences.ignoreRemoteClipboard == false)
        #expect(preferences.isPaused == false)
        #expect(preferences.captureImages == true)
        #expect(preferences.captureFiles == true)
        #expect(preferences.maxItemBytes == 20 * 1024 * 1024)
        #expect(preferences.captureSettings == CaptureSettings())
        #expect(preferences.forgetAfter == .never)
    }

    @Test("Saves how long unpinned clips stay, and falls back to never")
    func persistsForgetAfter() throws {
        defer { cleanUp() }
        let defaults = try makeDefaults()
        let preferences = Preferences(defaults: defaults)
        preferences.forgetAfter = .week
        #expect(defaults.string(forKey: "forgetAfter") == "week")
        #expect(Preferences(defaults: defaults).forgetAfter == .week)
        defaults.set("fortnight", forKey: "forgetAfter")
        #expect(Preferences(defaults: defaults).forgetAfter == .never)
    }

    @Test("Saves changes for the next launch")
    func persistsChanges() throws {
        defer { cleanUp() }
        do {
            let preferences = Preferences(defaults: try makeDefaults())
            preferences.historyLimit = 1200
            preferences.pasteDirectly = false
            preferences.alwaysPastePlainText = true
            preferences.panelPosition = .mouse
            preferences.excludedBundleIDs = ["com.example.Vault"]
            preferences.ignoreRemoteClipboard = true
            preferences.isPaused = true
            preferences.captureImages = false
            preferences.captureFiles = false
            preferences.maxItemBytes = 5 * 1024 * 1024
        }

        let reloaded = Preferences(defaults: try makeDefaults())
        #expect(reloaded.historyLimit == 1200)
        #expect(reloaded.pasteDirectly == false)
        #expect(reloaded.alwaysPastePlainText == true)
        #expect(reloaded.panelPosition == .mouse)
        #expect(reloaded.excludedBundleIDs == ["com.example.Vault"])
        #expect(reloaded.ignoreRemoteClipboard == true)
        #expect(reloaded.isPaused == true)
        #expect(reloaded.captureImages == false)
        #expect(reloaded.captureFiles == false)
        #expect(reloaded.maxItemBytes == 5 * 1024 * 1024)
    }

    @Test("Clamps the history limit and item size")
    func clampsValues() throws {
        defer { cleanUp() }
        let defaults = try makeDefaults()
        let preferences = Preferences(defaults: defaults)

        preferences.historyLimit = 10
        #expect(preferences.historyLimit == 50)
        preferences.historyLimit = 20_000
        #expect(preferences.historyLimit == 10_000)
        #expect(defaults.integer(forKey: "historyLimit") == 10_000)

        preferences.maxItemBytes = 0
        #expect(preferences.maxItemBytes == PreferenceDefaults.maxItemBytesRange.lowerBound)
    }

    @Test("Falls back to defaults for missing, invalid or out-of-range values")
    func toleratesBadValues() throws {
        defer { cleanUp() }
        let defaults = try makeDefaults()
        defaults.set("lots", forKey: "historyLimit")
        defaults.set("nowhere", forKey: "panelPosition")
        defaults.set("yes", forKey: "isPaused")
        defaults.set(999_999, forKey: "maxItemBytes")

        let preferences = Preferences(defaults: defaults)
        #expect(preferences.historyLimit == 500)
        #expect(preferences.panelPosition == .activeScreenCenter)
        #expect(preferences.isPaused == false)
        #expect(preferences.maxItemBytes == PreferenceDefaults.maxItemBytesRange.lowerBound)

        defaults.set(3, forKey: "historyLimit")
        #expect(Preferences(defaults: defaults).historyLimit == 50)
    }

    @Test("Hands capture a snapshot of its settings")
    func producesCaptureSettings() throws {
        defer { cleanUp() }
        let preferences = Preferences(defaults: try makeDefaults())
        preferences.isPaused = true
        preferences.excludedBundleIDs = ["com.Example.Vault"]
        preferences.ignoreRemoteClipboard = true
        preferences.captureImages = false
        preferences.maxItemBytes = 2 * 1024 * 1024

        let settings = preferences.captureSettings
        #expect(settings.isPaused)
        #expect(settings.excludes(bundleID: "com.example.vault"))
        #expect(!settings.excludes(bundleID: "com.1password.1password"))
        #expect(settings.ignoreRemoteClipboard)
        #expect(!settings.captureImages)
        #expect(settings.captureFiles)
        #expect(settings.maxItemBytes == 2 * 1024 * 1024)
    }

    @Test("Adds excluded apps once, at the end, ignoring case and blanks")
    func excludesApps() throws {
        defer { cleanUp() }
        let preferences = Preferences(defaults: try makeDefaults())
        preferences.excludedBundleIDs = ["com.apple.Passwords"]

        #expect(preferences.excludeApp("com.example.Vault"))
        #expect(!preferences.excludeApp("COM.EXAMPLE.VAULT"))
        #expect(!preferences.excludeApp("com.apple.passwords"))
        #expect(!preferences.excludeApp("  "))
        #expect(preferences.excludeApp(" org.example.Notes\n"))
        #expect(preferences.excludedBundleIDs == ["com.apple.Passwords", "com.example.Vault", "org.example.Notes"])
        #expect(preferences.isExcluded("com.EXAMPLE.vault"))
        #expect(!preferences.isExcluded("com.example.Other"))
        #expect(preferences.captureSettings.excludes(bundleID: "org.example.notes"))
    }

    @Test("Removes excluded apps and keeps the rest in order")
    func removesExcludedApps() throws {
        defer { cleanUp() }
        let preferences = Preferences(defaults: try makeDefaults())
        preferences.excludedBundleIDs = ["a.one", "b.two", "c.three", "d.four"]

        preferences.removeExcludedApps(["B.TWO", "d.four", "not.there"])
        #expect(preferences.excludedBundleIDs == ["a.one", "c.three"])
        preferences.removeExcludedApps([])
        #expect(preferences.excludedBundleIDs == ["a.one", "c.three"])
        #expect(Preferences(defaults: try makeDefaults()).excludedBundleIDs == ["a.one", "c.three"])
    }

    @Test("Restores the default excluded apps")
    func restoresDefaultExcludedApps() throws {
        defer { cleanUp() }
        let preferences = Preferences(defaults: try makeDefaults())
        #expect(preferences.excludedAppsAreDefault)

        preferences.excludeApp("com.example.Vault")
        preferences.removeExcludedApps(["com.apple.Passwords"])
        #expect(!preferences.excludedAppsAreDefault)

        preferences.restoreDefaultExcludedApps()
        #expect(preferences.excludedAppsAreDefault)
        #expect(preferences.excludedBundleIDs == PreferenceDefaults.excludedBundleIDs)
        #expect(Preferences(defaults: try makeDefaults()).excludedAppsAreDefault)
    }

    @Test("Offers the standard history sizes, plus the current one if it's different")
    func historyLimitChoices() {
        #expect(PreferenceDefaults.historyLimitChoices == [100, 250, 500, 1_000, 2_500, 5_000, 10_000])
        #expect(PreferenceDefaults.historyLimitChoices.contains(PreferenceDefaults.historyLimit))
        #expect(PreferenceDefaults.historyLimitChoices.allSatisfy(PreferenceDefaults.historyLimitRange.contains))
        #expect(PreferenceDefaults.historyLimitChoices(including: 500) == PreferenceDefaults.historyLimitChoices)
        #expect(PreferenceDefaults.historyLimitChoices(including: 1_200) == [100, 250, 500, 1_000, 1_200, 2_500, 5_000, 10_000])
        #expect(PreferenceDefaults.historyLimitChoices(including: 50).first == 50)
    }

    @Test("Notifies observers of changes")
    func notifiesObservers() throws {
        defer { cleanUp() }
        let preferences = Preferences(defaults: try makeDefaults())
        final class Flag: @unchecked Sendable { var raised = false }
        let flag = Flag()
        withObservationTracking { _ = preferences.isPaused } onChange: { flag.raised = true }

        preferences.isPaused = true
        #expect(flag.raised)
    }
}
