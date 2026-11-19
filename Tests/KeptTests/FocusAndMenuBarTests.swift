import AppKit
import Testing
@testable import Kept

@MainActor
@Suite("Focus return and the menu bar item")
struct FocusAndMenuBarTests {
    @Test("Closing a Kept window gives the keyboard to the last app, or hides Kept")
    func focusReturn() {
        // The usual case: back to the app the user was in last.
        #expect(FocusReturn.choice(isKeptActive: true, otherWindowIsOpen: false, lastOtherApp: 412) == .activate(processID: 412))
        // Relaunching Kept activated it first and nothing else was noted:
        // hide, so Kept doesn't stay active with no window.
        #expect(FocusReturn.choice(isKeptActive: true, otherWindowIsOpen: false, lastOtherApp: nil) == .hide)
        // Another Kept window still needs the keyboard.
        #expect(FocusReturn.choice(isKeptActive: true, otherWindowIsOpen: true, lastOtherApp: 412) == .stay)
        #expect(FocusReturn.choice(isKeptActive: true, otherWindowIsOpen: true, lastOtherApp: nil) == .stay)
        // Kept isn't active: someone else already has the keyboard.
        #expect(FocusReturn.choice(isKeptActive: false, otherWindowIsOpen: false, lastOtherApp: 412) == .stay)
        #expect(FocusReturn.choice(isKeptActive: false, otherWindowIsOpen: false, lastOtherApp: nil) == .stay)
    }

    @Test("Right-click, ⌃-click and ⌥-click open the menu; other clicks toggle the panel")
    func clickRouting() {
        #expect(!StatusItemController.wantsMenu(.leftMouseUp, modifiers: []))
        #expect(StatusItemController.wantsMenu(.rightMouseUp, modifiers: []))
        #expect(StatusItemController.wantsMenu(.leftMouseUp, modifiers: .control))
        #expect(StatusItemController.wantsMenu(.leftMouseUp, modifiers: .option))
        #expect(StatusItemController.wantsMenu(.leftMouseUp, modifiers: [.option, .shift]))
        #expect(!StatusItemController.wantsMenu(.leftMouseUp, modifiers: .command))
        #expect(!StatusItemController.wantsMenu(.leftMouseUp, modifiers: .shift))
        // No event (an action sent some other way): the panel.
        #expect(!StatusItemController.wantsMenu(nil, modifiers: .control))
    }

    @Test("The menu bar icon shows unless turned off")
    func menuBarIconPreference() throws {
        let suiteName = "app.kept.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preference = MenuBarIconPreference(defaults: defaults)
        #expect(preference.isShown)
        preference.isShown = false
        #expect(!MenuBarIconPreference(defaults: defaults).isShown)
        preference.isShown = true
        #expect(defaults.bool(forKey: MenuBarIconPreference.key))
    }
}
