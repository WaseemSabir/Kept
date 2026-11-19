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

    @Test("Caps characters glued together with joiners, tags and modifiers", arguments: [
        "\u{200D}", "\u{200C}", "\u{E0061}", "\u{1F3FD}", "\u{FE0F}", "\u{0301}\u{200D}", "\u{200D}👍",
        "\u{0301}\u{1F3FD}\u{E0062}\u{200D}",
    ])
    func capsGluedCharacters(glue: String) {
        let hostile = "a" + String(repeating: glue, count: 5_000) + "b c"
        for result in [TextSanitizer.singleLine(hostile), TextSanitizer.searchable(hostile)] {
            #expect(result.allSatisfy { $0.unicodeScalars.count <= TextSanitizer.maxScalarsPerCharacter })
            #expect(result.unicodeScalars.filter { $0.properties.generalCategory == .nonspacingMark }.count
                <= TextSanitizer.maxCombiningMarks)
            #expect(result.hasSuffix("b c"), "lost the text after the glue: \(result.unicodeScalars.count) scalars")
            #expect(result.unicodeScalars.last?.value != 0x200D)
        }
    }

    @Test("Caps an emoji ZWJ chain and keeps real sequences whole")
    func capsZWJChains() {
        let chain = String(repeating: "😀\u{200D}", count: 3_000) + "😀"
        let title = TextSanitizer.singleLine(chain + " end")
        #expect(title.allSatisfy { $0.unicodeScalars.count <= TextSanitizer.maxScalarsPerCharacter })
        #expect(title.hasSuffix(" end"))

        let family = "👨🏽\u{200D}👩🏽\u{200D}👧🏽\u{200D}👦🏽"  // 11 scalars
        #expect(TextSanitizer.singleLine(family) == family)
        #expect(TextSanitizer.searchable("\(family) ok") == "\(family) ok")
    }

    @Test("Never empties the search text of visible text")
    func keepsSearchTextNonEmpty() {
        let giant = "x" + String(repeating: "\u{0301}\u{200D}", count: 10_000)
        #expect(!TextSanitizer.searchable(giant).isEmpty)
        #expect(!TextSanitizer.searchable(giant, maxUTF8Bytes: 4).isEmpty)
        #expect(TextSanitizer.searchable("👍🏽", maxUTF8Bytes: 4) == "👍")
        #expect(TextSanitizer.searchable("  \n ").isEmpty)
    }

    @Test("Doesn't end a title on a dangling joiner")
    func trimsDanglingJoiners() {
        #expect(TextSanitizer.singleLine("a\u{200D}b", maxCharacters: 1) == "a")
        #expect(TextSanitizer.singleLine("word\u{200D}") == "word")
        #expect(TextSanitizer.singleLine("👨\u{200D}👩\u{200D}👧") == "👨\u{200D}👩\u{200D}👧")
    }

    @Test("Sanitizes long hostile text in near-linear time")
    func sanitizesQuickly() {
        let hostile = String(repeating: "a" + String(repeating: "\u{200D}\u{1F3FD}\u{E0061}\u{0301}", count: 50), count: 20_000)
        let elapsed = ContinuousClock().measure {
            _ = TextSanitizer.singleLine(hostile)
            _ = TextSanitizer.searchable(hostile)
        }
        #expect(elapsed < .seconds(5))
    }

    @Test("Tells visible content from whitespace and invisible characters")
    func detectsVisibleContent() {
        #expect(TextSanitizer.hasVisibleContent(" x "))
        #expect(!TextSanitizer.hasVisibleContent(" \n\t\u{00A0}\u{200B}\u{FEFF}"))
        #expect(!TextSanitizer.hasVisibleContent(""))
    }
}
