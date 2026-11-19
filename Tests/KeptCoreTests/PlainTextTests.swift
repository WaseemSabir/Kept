import Foundation
import Testing
@testable import KeptCore

@Suite("Plain text of an item")
struct PlainTextTests {
    private static let rtf = #"{\rtf1\ansi Hello, \b world\b0}"#

    @Test("Prefers the string, then the URL, then RTF, then HTML")
    func order() {
        #expect(item((.string, "Hello"), (.html, "<b>Hi</b>"), (.rtf, Self.rtf)).plainText == "Hello")
        #expect(item((.html, "<b>Hi</b>"), (.url, "https://kept.app")).plainText == "https://kept.app")
        #expect(item((.html, "<b>Hi</b>"), (.rtf, Self.rtf)).plainText == "Hello, world")
        #expect(item((.html, "<p>Hello <b>world</b></p><p>again</p>")).plainText == "Hello world\nagain")
    }

    @Test("Skips a blank string for the rich text next to it, but keeps one on its own")
    func blankStrings() {
        #expect(item((.string, "  "), (.html, "<i>styled</i>")).plainText == "styled")
        #expect(item((.string, " \t ")).plainText == " \t ")
        #expect(item((.string, "")).plainText == nil)
    }

    @Test("Strips trailing NULs and has no text for images")
    func edges() {
        #expect(item((.string, "abc\u{0}\u{0}")).plainText == "abc")
        #expect(PasteboardItem([ClipRepresentation(.png, Data([0x89, 0x50]))]).plainText == nil)
        #expect(item((.html, "<img src=x>")).plainText == nil)
    }

    @Test("Joins every item's text")
    func joinsItems() {
        let items = [item((.string, "one")), item((.html, "<b>two</b>")), item((.png, "not text"))]
        #expect(PasteboardItem.plainText(of: items) == "one\ntwo")
        #expect(PasteboardItem.plainText(of: [item((.png, "x"))]) == nil)
        #expect(PasteboardItem.plainText(of: []) == nil)
    }
}
