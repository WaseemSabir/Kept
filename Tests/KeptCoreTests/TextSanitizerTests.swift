import Testing
@testable import KeptCore

@Suite("Text sanitizer")
struct TextSanitizerTests {
    @Test("Collapses whitespace and line breaks into single spaces")
    func collapsesWhitespace() {
        #expect(TextSanitizer.singleLine("  Meeting\n\n\tnotes \r\n for\u{00A0}Thursday  ") == "Meeting notes for Thursday")
    }

    @Test("Drops control and format characters")
    func dropsInvisibleCharacters() {
        let text = "a\u{0000}b\u{0007}c\u{200B}d\u{202E}e\u{2066}f\u{FEFF}g\u{FFFF}h"
        #expect(TextSanitizer.singleLine(text) == "abcdefgh")
    }

    @Test("Keeps emoji sequences and joiners intact")
    func keepsEmoji() {
        let family = "👨‍👩‍👧"
        let scotland = "🏴󠁧󠁢󠁳󠁣󠁴󠁿"
        let thumbs = "👍🏽"
        #expect(TextSanitizer.singleLine("\(family) \(scotland) \(thumbs)") == "\(family) \(scotland) \(thumbs)")
    }

    @Test("Caps runs of combining marks")
    func capsCombiningMarks() {
        let zalgo = "Z" + String(repeating: "\u{0301}", count: 50) + "a"
        let sanitized = TextSanitizer.singleLine(zalgo)
        #expect(sanitized.unicodeScalars.count == 1 + TextSanitizer.maxCombiningMarks + 1)
        #expect(TextSanitizer.singleLine("Cafe\u{0301}") == "Cafe\u{0301}")
    }

    @Test("Limits titles to the character count")
    func limitsTitleLength() {
        let long = String(repeating: "word ", count: 1000)
        let title = TextSanitizer.singleLine(long, maxCharacters: 1000)
        #expect(title.count == 1000)
        #expect(TextSanitizer.singleLine(String(repeating: "👍🏽", count: 1200)).count == 1000)
    }

    @Test("Limits search text to whole characters within the byte budget")
    func limitsSearchText() {
        let text = String(repeating: "é", count: 10_000)  // 2 bytes each
        let searchable = TextSanitizer.searchable(text, maxUTF8Bytes: 8 * 1024)
        #expect(searchable.utf8.count == 8 * 1024)
        #expect(searchable.allSatisfy { $0 == "é" })

        let odd = TextSanitizer.searchable("a" + text, maxUTF8Bytes: 8 * 1024)
        #expect(odd.utf8.count == 8 * 1024 - 1)
    }

    @Test("Tells visible content from whitespace and invisible characters")
    func detectsVisibleContent() {
        #expect(TextSanitizer.hasVisibleContent(" x "))
        #expect(!TextSanitizer.hasVisibleContent(" \n\t\u{00A0}\u{200B}\u{FEFF}"))
        #expect(!TextSanitizer.hasVisibleContent(""))
    }
}
