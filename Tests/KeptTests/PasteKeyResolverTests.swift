import Testing
@testable import Kept

@Suite("Paste key resolver")
struct PasteKeyResolverTests {
    /// A layout as two tables: what each key types, and what it types with ⌘.
    private struct FakeLayout: KeyTranslating {
        var plain: [UInt16: String]
        var command: [UInt16: String]? = nil

        func characters(forKeyCode keyCode: UInt16, withCommand: Bool) -> String? {
            withCommand ? (command ?? plain)[keyCode] : plain[keyCode]
        }
    }

    // Key codes by QWERTY position.
    private static let qwertyV: UInt16 = 9
    private static let qwertyPeriod: UInt16 = 47
    private static let qwertyK: UInt16 = 40

    private static let qwerty = FakeLayout(plain: [0: "a", 8: "c", qwertyV: "v", qwertyK: "k", qwertyPeriod: "."])
    /// Dvorak types "v" on QWERTY's period key and "k" on QWERTY's V key.
    private static let dvorak = FakeLayout(plain: [0: "a", 8: "j", qwertyV: "k", qwertyPeriod: "v"])
    /// "Dvorak – QWERTY ⌘": Dvorak, but QWERTY while ⌘ is held.
    private static let dvorakQwertyCommand = FakeLayout(plain: dvorak.plain, command: qwerty.plain)
    /// A non-Latin layout: no key types "v", with or without ⌘.
    private static let russian = FakeLayout(plain: [0: "ф", 8: "с", qwertyV: "м", qwertyPeriod: "ю"])

    @Test("QWERTY pastes with the V key")
    func qwerty() {
        #expect(PasteKeyResolver.keyCode(in: [Self.qwerty]) == Self.qwertyV)
    }

    @Test("Dvorak pastes with the key that types v")
    func dvorak() {
        #expect(PasteKeyResolver.keyCode(in: [Self.dvorak, Self.qwerty]) == Self.qwertyPeriod)
    }

    @Test("A layout that turns QWERTY under ⌘ pastes with QWERTY's V")
    func qwertyUnderCommand() {
        #expect(PasteKeyResolver.keyCode(in: [Self.dvorakQwertyCommand, Self.qwerty]) == Self.qwertyV)
    }

    @Test("A non-Latin layout falls back to the ASCII-capable layout")
    func nonLatin() {
        #expect(PasteKeyResolver.keyCode(in: [Self.russian, Self.dvorak]) == Self.qwertyPeriod)
        #expect(PasteKeyResolver.keyCode(in: [Self.russian, Self.qwerty]) == Self.qwertyV)
    }

    @Test("With no layout that types v, the ANSI V key")
    func fallback() {
        #expect(PasteKeyResolver.keyCode(in: []) == PasteKeyResolver.ansiV)
        #expect(PasteKeyResolver.keyCode(in: [Self.russian]) == PasteKeyResolver.ansiV)
        #expect(PasteKeyResolver.ansiV == 9)
    }

    @Test("The ANSI V key wins over another key that also types v; case doesn't matter")
    func prefersANSIV() {
        let doubled = FakeLayout(plain: [3: "v", Self.qwertyV: "V"])
        #expect(PasteKeyResolver.keyCode(in: [doubled]) == Self.qwertyV)
        let elsewhere = FakeLayout(plain: [3: "v", Self.qwertyV: "b"])
        #expect(PasteKeyResolver.keyCode(in: [elsewhere]) == 3)
    }

    @Test("The ⌘ table counts before the plain one")
    func commandTableFirst() {
        let layout = FakeLayout(plain: [3: "v"], command: [Self.qwertyK: "v"])
        #expect(PasteKeyResolver.keyCode(in: [layout]) == Self.qwertyK)
        let noCommandV = FakeLayout(plain: [3: "v"], command: [3: "x"])
        #expect(PasteKeyResolver.keyCode(in: [noCommandV]) == 3)
    }
}
