/// A key-down event reduced to what the panel's shortcuts look at, so key
/// routing is a pure function that tests can drive without `NSEvent`.
struct KeyPress: Equatable, Sendable {
    struct Modifiers: OptionSet, Hashable, Sendable {
        let rawValue: UInt8

        static let command = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let control = Modifiers(rawValue: 1 << 2)
        static let shift = Modifiers(rawValue: 1 << 3)
    }

    /// The hardware key code (Carbon's `kVK_*`), for keys that don't type
    /// characters: arrows, Return, Tab, Delete…
    var keyCode: UInt16
    var modifiers: Modifiers
    /// The characters the key produces in the current layout without
    /// modifiers (`NSEvent.charactersIgnoringModifiers`), so letter shortcuts
    /// follow the layout: ⌘P is the key that types "p".
    var characters: String

    init(keyCode: UInt16, modifiers: Modifiers = [], characters: String = "") {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.characters = characters
    }
}
