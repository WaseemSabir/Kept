import Testing
@testable import KeptCore

@Suite("App activation log")
struct AppActivationLogTests {
    private let settings = CaptureSettings()
    private let safari = "com.apple.Safari"
    private let onePassword = "com.1password.1password"

    private func log(_ activations: (String?, Double)...) -> AppActivationLog {
        var log = AppActivationLog()
        for (bundleID, time) in activations {
            log.record(bundleID, at: time)
        }
        return log
    }

    @Test("A password manager that copied and handed focus back between polls is caught")
    func quickSwitchInsideTheWindow() {
        // Safari in front; the password manager's quick-access window comes
        // up, copies, and Safari is back before the next poll at 10.5.
        let log = log((safari, 0), (onePassword, 10.1), (safari, 10.3))
        #expect(log.frontmostApps(from: 10.0, through: 10.5) == [safari, onePassword])
        #expect(log.excludedApp(from: 10.0, through: 10.5, settings: settings) == onePassword)
    }

    @Test("The app in front when the window opens counts")
    func appInFrontAtTheStart() {
        let log = log((onePassword, 0), (safari, 10.3))
        #expect(log.excludedApp(from: 10.0, through: 10.5, settings: settings) == onePassword)
    }

    @Test("Apps in front only before or after the window don't count")
    func outsideTheWindow() {
        let before = log((onePassword, 0), (safari, 5))
        #expect(before.frontmostApps(from: 10, through: 10.5) == [safari])
        #expect(before.excludedApp(from: 10, through: 10.5, settings: settings) == nil)

        let after = log((safari, 0), (onePassword, 11))
        #expect(after.excludedApp(from: 10, through: 10.5, settings: settings) == nil)
    }

    @Test("Lists each app once, matches exclusions without regard to case, and skips apps without an ID")
    func repeatsCaseAndNil() {
        let log = log((safari, 0), (nil, 1), (safari.uppercased(), 2), ("COM.BITWARDEN.DESKTOP", 3))
        #expect(log.frontmostApps(from: 0, through: 5) == [safari, "COM.BITWARDEN.DESKTOP"])
        #expect(log.excludedApp(from: 0, through: 5, settings: settings) == "COM.BITWARDEN.DESKTOP")
        #expect(log.excludedApp(from: 0, through: 5, settings: CaptureSettings(excludedBundleIDs: [])) == nil)
    }

    @Test("Knows nothing before its first activation")
    func empty() {
        #expect(AppActivationLog().frontmostApps(from: 0, through: 100).isEmpty)
        #expect(log((safari, 50)).frontmostApps(from: 0, through: 100) == [safari])
    }

    @Test("Drops old activations but keeps the one still in front")
    func retention() {
        let retention = AppActivationLog.retention
        let log = log(("a", 0), ("b", 10), ("c", retention + 20))
        #expect(log.activations.map(\.bundleID) == ["b", "c"])
        #expect(log.frontmostApps(from: retention + 15, through: retention + 16) == ["b"])
    }

    @Test("Puts a late activation in its place")
    func outOfOrder() {
        let log = log((safari, 0), (safari, 10), (onePassword, 5))
        #expect(log.activations.map(\.time) == [0, 5, 10])
        #expect(log.frontmostApps(from: 6, through: 7) == [onePassword])
    }
}
