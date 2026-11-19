/// Maps key presses in the panel to commands.
///
/// The search field always has focus, so plain letters, ⌫ and ←/→ return
/// `nil` and go on to the field. Every list action uses a modifier or a key
/// that doesn't type. Letter shortcuts match the character the key types in
/// the current layout; digits also match by key position, because some
/// layouts (AZERTY) need ⇧ to type them.
///
/// While a name or text is being edited (`PanelKeyMode`), keys belong to
/// the field: ⏎ (renaming), ⌘S and ⌘⏎ save, Esc cancels the edit (not the
/// panel), the editing shortcuts are sent to the field, and every other ⌘
/// shortcut is taken and does nothing, so ⌘1–9 or ⌘P can't paste or pin
/// meanwhile. ⌘ with an arrow, ⌫ or ⌦ still moves and deletes in the text.
enum PanelKeyRouter {
    /// Carbon virtual key codes (`kVK_*`) of the keys the panel handles.
    enum KeyCode {
        static let returnKey: UInt16 = 36
        static let tab: UInt16 = 48
        static let delete: UInt16 = 51
        static let escape: UInt16 = 53
        static let keypadEnter: UInt16 = 76
        static let home: UInt16 = 115
        static let pageUp: UInt16 = 116
        static let forwardDelete: UInt16 = 117
        static let end: UInt16 = 119
        static let pageDown: UInt16 = 121
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124
        static let downArrow: UInt16 = 125
        static let upArrow: UInt16 = 126
    }

    /// The number keys 1–9 on the top row, by position.
    static let digitKeyCodes: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
    ]

    /// Keys that move through or delete text, with or without ⌘ or ⌥.
    static let textNavigationKeyCodes: Set<UInt16> = [
        KeyCode.leftArrow, KeyCode.rightArrow, KeyCode.downArrow, KeyCode.upArrow, KeyCode.delete, KeyCode.forwardDelete,
        KeyCode.home, KeyCode.end, KeyCode.pageUp, KeyCode.pageDown,
    ]

    static func command(for press: KeyPress, mode: PanelKeyMode = .browsing) -> PanelCommand? {
        switch mode {
        case .browsing: browsingCommand(for: press)
        case .renaming, .editingText: editingCommand(for: press, mode: mode)
        }
    }

    private static func browsingCommand(for press: KeyPress) -> PanelCommand? {
        let modifiers = press.modifiers
        switch press.keyCode {
        case KeyCode.upArrow:
            return arrow(modifiers, step: -1, jump: .selectFirst)
        case KeyCode.downArrow:
            return arrow(modifiers, step: 1, jump: .selectLast)
        case KeyCode.home where modifiers.isEmpty:
            return .selectFirst
        case KeyCode.end where modifiers.isEmpty:
            return .selectLast
        case KeyCode.pageUp where modifiers.isEmpty:
            return .movePage(by: -1)
        case KeyCode.pageDown where modifiers.isEmpty:
            return .movePage(by: 1)
        case KeyCode.returnKey, KeyCode.keypadEnter:
            switch modifiers {
            case []: return .activate(alternate: false)
            case .option: return .activate(alternate: true)
            case .command: return .copyOnly
            default: return nil
            }
        case KeyCode.delete, KeyCode.forwardDelete:
            switch modifiers {
            case .command: return .delete
            case [.command, .option]: return .requestClearUnpinned
            default: return nil
            }
        case KeyCode.escape where modifiers.isEmpty:
            return .cancel
        case KeyCode.tab:
            switch modifiers {
            case []: return .nextFilter
            case .shift: return .previousFilter
            default: return nil
            }
        default:
            return characterCommand(for: press)
        }
    }

    private static func arrow(
        _ modifiers: KeyPress.Modifiers,
        step: Int,
        jump: PanelCommand
    ) -> PanelCommand? {
        switch modifiers {
        case []: .moveSelection(by: step)
        case .command: jump
        case [.command, .option]: .movePin(by: step)
        default: nil
        }
    }

    /// Shortcuts named by the character their key types.
    private static func characterCommand(for press: KeyPress) -> PanelCommand? {
        let character = press.characters.lowercased()
        switch press.modifiers {
        case .control:
            switch character {
            case "p": return .moveSelection(by: -1)
            case "n": return .moveSelection(by: 1)
            case "u": return .clearQuery
            default: return nil
            }
        case .command:
            if let row = digit(of: press) { return .activateRow(row - 1, alternate: false) }
            switch character {
            case "p": return .togglePin
            case "r": return .beginRename
            case "e": return .beginTextEdit
            case "x": return .edit(.cut)
            case "c": return .edit(.copy)
            case "v": return .edit(.paste)
            case "a": return .edit(.selectAll)
            case "z": return .edit(.undo)
            case ",": return .openSettings
            default: return nil
            }
        case [.command, .shift]:
            return character == "z" ? .edit(.redo) : nil
        case [.command, .option]:
            return digit(of: press).map { .activateRow($0 - 1, alternate: true) }
        default:
            return nil
        }
    }

    /// Keys while a name (`.renaming`) or text (`.editingText`) is being
    /// edited.
    private static func editingCommand(for press: KeyPress, mode: PanelKeyMode) -> PanelCommand? {
        let modifiers = press.modifiers
        switch press.keyCode {
        case KeyCode.escape:
            return modifiers.isEmpty ? .cancelEditing : nil
        case KeyCode.returnKey, KeyCode.keypadEnter:
            if modifiers == .command { return .commitEditing }
            guard mode == .renaming else { return nil }  // a line break in the text
            // ⌥⏎ would put a line break in a one-line name.
            return modifiers.isEmpty ? .commitEditing : .ignore
        case KeyCode.tab:
            // Tab indents text; anything else would move the keyboard away.
            return mode == .editingText && modifiers.isEmpty ? nil : .ignore
        default:
            break
        }
        // Typing, ⌥ characters and ⌃ text bindings go to the field.
        guard modifiers.contains(.command) else { return nil }
        if textNavigationKeyCodes.contains(press.keyCode) { return nil }

        let character = press.characters.lowercased()
        switch modifiers {
        case .command:
            switch character {
            case "x": return .edit(.cut)
            case "c": return .edit(.copy)
            case "v": return .edit(.paste)
            case "a": return .edit(.selectAll)
            case "z": return .edit(.undo)
            case "s": return .commitEditing
            default: return .ignore
            }
        case [.command, .shift]:
            return character == "z" ? .edit(.redo) : .ignore
        default:
            return .ignore
        }
    }

    /// 1–9 from the typed character, or from the key's position.
    private static func digit(of press: KeyPress) -> Int? {
        if press.characters.count == 1, let value = Int(press.characters), (1...9).contains(value) {
            return value
        }
        return digitKeyCodes[press.keyCode]
    }
}
