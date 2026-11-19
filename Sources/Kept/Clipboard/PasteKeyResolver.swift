/// Answers "what does this key type?" for one keyboard layout.
/// `UnicodeKeyLayout` reads a real layout; tests pass tables.
protocol KeyTranslating: Sendable {
    /// The characters `keyCode` types, with ⌘ held or not; `nil` if none.
    func characters(forKeyCode keyCode: UInt16, withCommand: Bool) -> String?
}

/// Finds the virtual key code to post for ⌘V.
///
/// `kVK_ANSI_V` is a key *position*; on Dvorak, AZERTY-like or custom
/// layouts another key types "v", and apps match ⌘V by the character. So:
///
/// 1. Each layout is asked with ⌘ held first. Layouts such as "Dvorak –
///    QWERTY ⌘" switch to QWERTY while ⌘ is down, and apps see the ⌘
///    character, so that's the key that pastes.
/// 2. Then without modifiers, for layouts whose ⌘ table has no "v".
/// 3. Layouts are tried in order: the current one, then the current
///    ASCII-capable one. Non-Latin layouts (Russian, Greek, Hebrew…) type no
///    "v" at all; AppKit matches their shortcuts on the ASCII-capable
///    layout, so its V key is right.
/// 4. If nothing types "v", `kVK_ANSI_V`.
///
/// Within a layout, the ANSI V key wins when it types "v", so a layout
/// that also has "v" elsewhere (a keypad, an ISO key) keeps the usual key.
enum PasteKeyResolver {
    /// `kVK_ANSI_V`.
    static let ansiV: UInt16 = 9
    /// Every virtual key code a layout maps.
    static let keyCodes: Range<UInt16> = 0..<128

    static func keyCode(typing character: String = "v", in layouts: [any KeyTranslating]) -> UInt16 {
        for layout in layouts {
            for withCommand in [true, false] {
                if let keyCode = keyCode(typing: character, in: layout, withCommand: withCommand) {
                    return keyCode
                }
            }
        }
        return ansiV
    }

    private static func keyCode(typing character: String, in layout: any KeyTranslating, withCommand: Bool) -> UInt16? {
        func types(_ keyCode: UInt16) -> Bool {
            layout.characters(forKeyCode: keyCode, withCommand: withCommand)?.lowercased() == character
        }
        if types(ansiV) { return ansiV }
        return keyCodes.first(where: types)
    }
}
