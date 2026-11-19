import AppKit
import Testing
@testable import Kept

@MainActor
@Suite("Welcome window and clipboard access")
struct WelcomeTests {
    @Test("The welcome window opens by itself once")
    func shownOnce() throws {
        let suiteName = "app.kept.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let state = WelcomeState(defaults: defaults)
        #expect(state.shouldShowAtLaunch)
        state.hasBeenShown = true
        #expect(!WelcomeState(defaults: defaults).shouldShowAtLaunch)
        #expect(defaults.bool(forKey: WelcomeState.key))
    }

    @Test("The open line names the recorded shortcut, or only the icon")
    func openLine() {
        #expect(
            WelcomeCopy.openLine(shortcut: "⇧⌘V")
                == "Press ⇧⌘V in any app, or click Kept's icon in the menu bar, to see what you've copied."
        )
        #expect(WelcomeCopy.openLine(shortcut: "⌃⌘V").contains("⌃⌘V"))
        for missing in [nil, ""] as [String?] {
            #expect(
                WelcomeCopy.openLine(shortcut: missing)
                    == "Click Kept's icon in the menu bar to see what you've copied. You can set a shortcut in Settings."
            )
        }
    }

    @Test("Only Ask and Deny need attention; the default and Allow don't")
    func accessMapping() {
        if #available(macOS 15.4, *) {
            #expect(PasteboardAccess(NSPasteboard.AccessBehavior.default) == .allowed)
            #expect(PasteboardAccess(NSPasteboard.AccessBehavior.alwaysAllow) == .allowed)
            #expect(PasteboardAccess(NSPasteboard.AccessBehavior.ask) == .asks)
            #expect(PasteboardAccess(NSPasteboard.AccessBehavior.alwaysDeny) == .denied)
        }
        #expect(!PasteboardAccess.allowed.needsAttention)
        #expect(PasteboardAccess.asks.needsAttention)
        #expect(PasteboardAccess.denied.needsAttention)
    }

    @Test("Clipboard access copy says what's wrong and where to change it, by macOS version")
    func accessCopy() {
        #expect(PasteboardAccess.allowed.problem == nil)
        #expect(PasteboardAccess.allowed.direction(osMajorVersion: 26) == nil)
        #expect(PasteboardAccess.denied.problem == "Kept can't see what you copy until you allow it.")
        #expect(
            PasteboardAccess.asks.direction(osMajorVersion: 15)
                == "macOS is set to ask each time Kept reads the clipboard. In System Settings › Privacy & Security › Paste from Other Apps, choose Allow for Kept."
        )
        #expect(PasteboardAccess.denied.direction(osMajorVersion: 26)?.hasPrefix("macOS is set to deny Kept access") == true)
        #expect(
            PasteboardAccess.denied.direction(osMajorVersion: 27)?.hasSuffix(
                "In System Settings › Privacy & Security, look for Paste from Other Apps and choose Allow for Kept."
            ) == true
        )
    }

    @Test("The system checker reads something sensible on any macOS")
    func systemAccess() {
        let access = SystemPasteboardAccess().access
        #expect([PasteboardAccess.allowed, .asks, .denied].contains(access))
    }
}
