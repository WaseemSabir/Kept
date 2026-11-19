import AppKit

extension KeyPress {
    /// Reads a key-down event. Only ⌘ ⌥ ⌃ ⇧ count as modifiers; Caps Lock,
    /// the Fn and numeric-pad flags (set on arrow keys) are ignored.
    init(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        self.init(
            keyCode: event.keyCode,
            modifiers: modifiers,
            characters: event.charactersIgnoringModifiers ?? ""
        )
    }
}
