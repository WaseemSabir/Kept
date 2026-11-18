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
