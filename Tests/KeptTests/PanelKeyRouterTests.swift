import Testing
@testable import Kept

@Suite("Panel key router")
struct PanelKeyRouterTests {
    private typealias Key = PanelKeyRouter.KeyCode

    private func command(
        _ keyCode: UInt16,
        _ modifiers: KeyPress.Modifiers = [],
        _ characters: String = ""
    ) -> PanelCommand? {
        PanelKeyRouter.command(for: KeyPress(keyCode: keyCode, modifiers: modifiers, characters: characters))
    }

    @Test("Arrows and ⌃P / ⌃N move the selection")
    func movement() {
        #expect(command(Key.upArrow) == .moveSelection(by: -1))
        #expect(command(Key.downArrow) == .moveSelection(by: 1))
        #expect(command(35, .control, "p") == .moveSelection(by: -1))
        #expect(command(45, .control, "n") == .moveSelection(by: 1))
        #expect(command(Key.upArrow, .command) == .selectFirst)
        #expect(command(Key.downArrow, .command) == .selectLast)
        #expect(command(Key.home) == .selectFirst)
        #expect(command(Key.end) == .selectLast)
        #expect(command(Key.pageUp) == .movePage(by: -1))
        #expect(command(Key.pageDown) == .movePage(by: 1))
    }

    @Test("Return pastes, ⌥ makes it plain text, ⌘ copies only")
    func returnKey() {
        #expect(command(Key.returnKey) == .activate(plainText: false))
        #expect(command(Key.keypadEnter) == .activate(plainText: false))
        #expect(command(Key.returnKey, .option) == .activate(plainText: true))
        #expect(command(Key.returnKey, .command) == .copyOnly)
        #expect(command(Key.returnKey, .shift) == nil)
    }

    @Test("⌘1–⌘9 act on a row; ⌥⌘ as plain text; digits match by position too")
    func quickPaste() {
        #expect(command(18, .command, "1") == .activateRow(0, plainText: false))
        #expect(command(25, .command, "9") == .activateRow(8, plainText: false))
        #expect(command(23, [.command, .option], "5") == .activateRow(4, plainText: true))
        // AZERTY: the 1 key types "&" without ⇧.
        #expect(command(18, .command, "&") == .activateRow(0, plainText: false))
        #expect(command(29, .command, "0") == nil)
    }

    @Test("Letter shortcuts follow the typed character, not the key position")
    func letterShortcuts() {
        // On Dvorak the key that types "p" is QWERTY's R (key code 15).
        #expect(command(15, .command, "p") == .togglePin)
        #expect(command(35, .command, "r") == nil)
        #expect(command(35, .command, "P") == .togglePin)
        #expect(command(32, .control, "u") == .clearQuery)
    }

    @Test("Delete needs ⌘; ⌥⌘⌫ asks to clear the history")
    func deletion() {
        #expect(command(Key.delete) == nil)
        #expect(command(Key.delete, .command) == .delete)
        #expect(command(Key.forwardDelete, .command) == .delete)
        #expect(command(Key.delete, [.command, .option]) == .requestClearUnpinned)
    }

    @Test("Esc cancels and Tab cycles the filter")
    func escapeAndTab() {
        #expect(command(Key.escape) == .cancel)
        #expect(command(Key.tab) == .nextFilter)
        #expect(command(Key.tab, .shift) == .previousFilter)
        #expect(command(Key.tab, .control) == nil)
    }

    @Test("Standard editing shortcuts go to the search field")
    func editing() {
        #expect(command(7, .command, "x") == .edit(.cut))
        #expect(command(8, .command, "c") == .edit(.copy))
        #expect(command(9, .command, "v") == .edit(.paste))
        #expect(command(0, .command, "a") == .edit(.selectAll))
        #expect(command(6, .command, "z") == .edit(.undo))
        #expect(command(6, [.command, .shift], "Z") == .edit(.redo))
    }

    @Test("Typing, ⌫ and ←/→ go to the search field")
    func typing() {
        #expect(command(0, [], "a") == nil)
        #expect(command(0, .shift, "A") == nil)
        #expect(command(123) == nil)
        #expect(command(124) == nil)
        #expect(command(Key.upArrow, .shift) == nil)
    }
}
