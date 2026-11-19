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

    @Test("Return pastes, ⌥ the other format, ⌘ copies only")
    func returnKey() {
        #expect(command(Key.returnKey) == .activate(alternate: false))
        #expect(command(Key.keypadEnter) == .activate(alternate: false))
        #expect(command(Key.returnKey, .option) == .activate(alternate: true))
        #expect(command(Key.returnKey, .command) == .copyOnly)
        #expect(command(Key.returnKey, .shift) == nil)
        #expect(command(Key.returnKey, [.command, .option]) == nil)
    }

    @Test("⌘1–⌘9 paste row N; ⌥⌘1–⌥⌘9 in the other format; digits match by position too")
    func quickPaste() {
        for (keyCode, digit) in PanelKeyRouter.digitKeyCodes {
            let character = String(digit)
            #expect(command(keyCode, .command, character) == .activateRow(digit - 1, alternate: false))
            #expect(command(keyCode, [.command, .option], character) == .activateRow(digit - 1, alternate: true))
            // AZERTY types symbols on the digit keys without ⇧; the position counts.
            #expect(command(keyCode, .command, "&") == .activateRow(digit - 1, alternate: false))
            // Without ⌘ the digit types into the search field.
            #expect(command(keyCode, [], character) == nil)
            #expect(command(keyCode, .option, character) == nil)
            #expect(command(keyCode, [.command, .shift], character) == nil)
        }
        #expect(command(29, .command, "0") == nil)
        #expect(command(29, [.command, .option], "0") == nil)
    }

    @Test("Paste keys turn into paste requests; other commands don't")
    func pasteRequests() {
        #expect(command(Key.returnKey)?.pasteRequest == .paste(alternate: false))
        #expect(command(Key.returnKey, .option)?.pasteRequest == .paste(alternate: true))
        #expect(command(Key.returnKey, .command)?.pasteRequest == .copyOnly)
        #expect(command(20, .command, "3")?.pasteRequest == .paste(alternate: false))
        #expect(command(20, [.command, .option], "3")?.pasteRequest == .paste(alternate: true))
        #expect(PanelCommand.togglePin.pasteRequest == nil)
        #expect(PanelCommand.cancel.pasteRequest == nil)
        #expect(PanelCommand.edit(.paste).pasteRequest == nil)
    }

    @Test("Letter shortcuts follow the typed character, not the key position")
    func letterShortcuts() {
        // On Dvorak the key that types "p" is QWERTY's R (key code 15).
        #expect(command(15, .command, "p") == .togglePin)
        #expect(command(35, .command, "j") == nil)
        // On Dvorak, QWERTY's O key (31) types "r" and QWERTY's D key (2) "e".
        #expect(command(31, .command, "r") == .beginRename)
        #expect(command(2, .command, "e") == .beginTextEdit)
        #expect(command(15, [], "r") == nil)
        #expect(command(14, [.command, .shift], "e") == nil)
        #expect(command(35, .command, "P") == .togglePin)
        #expect(command(32, .control, "u") == .clearQuery)
    }

    @Test("⌥⌘↑ / ⌥⌘↓ move the selected pin; ⌘, opens Settings")
    func pinMovesAndSettings() {
        #expect(command(Key.upArrow, [.command, .option]) == .movePin(by: -1))
        #expect(command(Key.downArrow, [.command, .option]) == .movePin(by: 1))
        #expect(command(Key.upArrow, .option) == nil)
        #expect(command(Key.downArrow, [.command, .shift]) == nil)
        #expect(command(43, .command, ",") == .openSettings)
        #expect(command(43, [], ",") == nil)
        #expect(command(43, [.command, .shift], ",") == nil)
        #expect(PanelCommand.movePin(by: 1).pasteRequest == nil)
        #expect(PanelCommand.openSettings.pasteRequest == nil)
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

    // MARK: Renaming and editing

    private func command(
        in mode: PanelKeyMode,
        _ keyCode: UInt16,
        _ modifiers: KeyPress.Modifiers = [],
        _ characters: String = ""
    ) -> PanelCommand? {
        PanelKeyRouter.command(for: KeyPress(keyCode: keyCode, modifiers: modifiers, characters: characters), mode: mode)
    }

    @Test("While renaming, ⏎ and ⌘S save, Esc cancels the rename, and ⌥⏎ and Tab do nothing")
    func renamingKeys() {
        #expect(command(in: .renaming, Key.returnKey) == .commitEditing)
        #expect(command(in: .renaming, Key.keypadEnter) == .commitEditing)
        #expect(command(in: .renaming, Key.returnKey, .command) == .commitEditing)
        #expect(command(in: .renaming, 1, .command, "s") == .commitEditing)
        #expect(command(in: .renaming, Key.escape) == .cancelEditing)
        #expect(command(in: .renaming, Key.returnKey, .option) == .ignore)
        #expect(command(in: .renaming, Key.tab) == .ignore)
        #expect(command(in: .renaming, Key.tab, .shift) == .ignore)
    }

    @Test("While editing text, ⌘S and ⌘⏎ save, Esc cancels, and ⏎ and Tab type")
    func editingKeys() {
        #expect(command(in: .editingText, 1, .command, "s") == .commitEditing)
        #expect(command(in: .editingText, Key.returnKey, .command) == .commitEditing)
        #expect(command(in: .editingText, Key.keypadEnter, .command) == .commitEditing)
        #expect(command(in: .editingText, Key.escape) == .cancelEditing)
        #expect(command(in: .editingText, Key.returnKey) == nil)
        #expect(command(in: .editingText, Key.returnKey, .option) == nil)
        #expect(command(in: .editingText, Key.returnKey, .shift) == nil)
        #expect(command(in: .editingText, Key.tab) == nil)
        #expect(command(in: .editingText, Key.tab, .shift) == .ignore)
    }

    @Test("While editing, list shortcuts are taken and do nothing")
    func editingSuppressesShortcuts() {
        for mode in [PanelKeyMode.renaming, .editingText] {
            for (keyCode, digit) in PanelKeyRouter.digitKeyCodes {
                #expect(command(in: mode, keyCode, .command, String(digit)) == .ignore)
                #expect(command(in: mode, keyCode, [.command, .option], String(digit)) == .ignore)
            }
            #expect(command(in: mode, 35, .command, "p") == .ignore)
            #expect(command(in: mode, 15, .command, "r") == .ignore)
            #expect(command(in: mode, 14, .command, "e") == .ignore)
            #expect(command(in: mode, 43, .command, ",") == .ignore)
            #expect(command(in: mode, 40, .command, "k") == .ignore)
            #expect(command(in: mode, 1, [.command, .shift], "S") == .ignore)
        }
    }

    @Test("While editing, typing, text keys and editing shortcuts go to the field")
    func editingPassesTextKeys() {
        for mode in [PanelKeyMode.renaming, .editingText] {
            #expect(command(in: mode, 0, [], "a") == nil)
            #expect(command(in: mode, 0, .shift, "A") == nil)
            #expect(command(in: mode, 0, .option, "å") == nil)
            #expect(command(in: mode, 32, .control, "u") == nil)
            #expect(command(in: mode, 35, .control, "p") == nil)
            #expect(command(in: mode, Key.delete) == nil)
            for keyCode in [Key.leftArrow, Key.rightArrow, Key.upArrow, Key.downArrow, Key.delete, Key.forwardDelete,
                            Key.home, Key.end, Key.pageUp, Key.pageDown] {
                #expect(command(in: mode, keyCode) == nil)
                #expect(command(in: mode, keyCode, .command) == nil)
                #expect(command(in: mode, keyCode, .option) == nil)
                #expect(command(in: mode, keyCode, [.command, .option]) == nil)
                #expect(command(in: mode, keyCode, [.command, .shift]) == nil)
            }
            #expect(command(in: mode, 7, .command, "x") == .edit(.cut))
            #expect(command(in: mode, 8, .command, "c") == .edit(.copy))
            #expect(command(in: mode, 9, .command, "v") == .edit(.paste))
            #expect(command(in: mode, 0, .command, "a") == .edit(.selectAll))
            #expect(command(in: mode, 6, .command, "z") == .edit(.undo))
            #expect(command(in: mode, 6, [.command, .shift], "Z") == .edit(.redo))
            #expect(command(in: mode, Key.escape, .shift) == nil)
        }
    }

    @Test("Browsing reads keys as before")
    func browsingIsTheDefault() {
        let press = KeyPress(keyCode: Key.escape)
        #expect(PanelKeyRouter.command(for: press) == .cancel)
        #expect(PanelKeyRouter.command(for: press, mode: .browsing) == .cancel)
        #expect(command(in: .browsing, 1, .command, "s") == nil)
    }
}

