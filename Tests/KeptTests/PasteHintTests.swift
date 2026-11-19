import Foundation
import Testing
@testable import Kept

@MainActor
@Suite("Paste hint")
struct PasteHintTests {
    @Test("The wording names Accessibility up to macOS 26 and only Privacy & Security after")
    func versionAwareCopy() {
        for version in [14, 15, 26] {
            let detail = PasteHintCopy.permissionDetail(osMajorVersion: version)
            #expect(detail.contains("Accessibility"))
            #expect(detail.contains("Privacy & Security settings"))
        }
        for version in [27, 28] {
            let detail = PasteHintCopy.permissionDetail(osMajorVersion: version)
            #expect(!detail.contains("Accessibility"))
            #expect(detail.contains("Privacy & Security settings"))
        }
        #expect(PasteHintCopy.title == "Copied. Press ⌘V to paste.")
        #expect(PasteHintCopy.title == "\(PasteHintCopy.titleBeforeKeys) \(PasteHintCopy.keys) \(PasteHintCopy.titleAfterKeys)")
        #expect(PasteHintCopy.allowButton == "Allow Kept to paste…")
    }

    @Test("The hint sits where the panel was, just above its bottom edge")
    func placementNearPanel() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let panel = CGRect(x: 360, y: 208, width: 720, height: 460)
        let frame = PasteHintController.frame(size: CGSize(width: 200, height: 36), anchor: panel, visibleFrame: screen)
        #expect(frame == CGRect(x: 620, y: 208 + Theme.Layout.hintPanelOffset, width: 200, height: 36))
    }

    @Test("With no panel the hint sits at the bottom center of the screen, and always on it")
    func placementOnScreen() {
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 850)
        let frame = PasteHintController.frame(size: CGSize(width: 200, height: 36), anchor: nil, visibleFrame: screen)
        #expect(frame == CGRect(x: 620, y: 25 + Theme.Layout.hintScreenOffset, width: 200, height: 36))

        // A panel hanging off the left edge still puts the hint on screen.
        let offscreen = CGRect(x: -700, y: -20, width: 720, height: 460)
        let clamped = PasteHintController.frame(size: CGSize(width: 300, height: 110), anchor: offscreen, visibleFrame: screen)
        #expect(clamped.minX == 0)
        #expect(clamped.minY == 25)
    }

    @Test("Hint memory persists in UserDefaults")
    func onboardingPersists() throws {
        let suiteName = "app.kept.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let onboarding = PasteOnboarding(defaults: defaults)
        #expect(!onboarding.hasRequestedAccess)
        #expect(!onboarding.hasShownPermissionHint)
        onboarding.hasRequestedAccess = true
        onboarding.hasShownPermissionHint = true

        let again = PasteOnboarding(defaults: defaults)
        #expect(again.hasRequestedAccess)
        #expect(again.hasShownPermissionHint)
        #expect(defaults.bool(forKey: PasteOnboarding.Key.requestedAccess))
        #expect(defaults.bool(forKey: PasteOnboarding.Key.shownPermissionHint))
    }
}
