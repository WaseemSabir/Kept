/// Answers "what does this key type?" for one keyboard layout.
/// `UnicodeKeyLayout` reads a real layout; tests pass tables.
protocol KeyTranslating: Sendable {
    /// The characters `keyCode` types, with ⌘ held or not; `nil` if none.
    func characters(forKeyCode keyCode: UInt16, withCommand: Bool) -> String?
}
