import Foundation
import Testing
@testable import KeptCore

@Suite("Rich text extraction")
struct RichTextExtractorTests {
    @Test("Reads text from a TextEdit-style RTF document")
    func readsRTF() {
        let rtf = #"""
        {\rtf1\ansi\ansicpg1252\cocoartf2761
        \cocoatextscaling0\cocoaplatform0{\fonttbl\f0\fswiss\fcharset0 Helvetica;}
        {\colortbl;\red255\green255\blue255;}
        {\*\expandedcolortbl;;}
        \paperw11900\paperh16840\margl1440\margr1440\vieww11520\viewh8400\viewkind0
        \pard\tx566\pardirnatural\partightenfactor0

        \f0\fs24 \cf0 Hello \b bold\b0  world\
        Caf\'e9 costs \'80 5 \{braces\} \\ done}
        """#
        #expect(RTFTextExtractor.plainText(from: Data(rtf.utf8)) == "Hello bold world\nCafé costs € 5 {braces} \\ done")
    }

    @Test("Decodes Unicode escapes, skipping their fallbacks")
    func readsUnicodeEscapes() {
        // "@" stands for a backslash-u escape.
        let rtf = #"{\rtf1\uc1 @19990?@30028? and \uc0@-10179@-9140  ok}"#.replacingOccurrences(of: "@", with: #"\u"#)
        #expect(RTFTextExtractor.plainText(from: Data(rtf.utf8)) == "世界 and 👌 ok")
    }

    @Test("Skips pictures and field instructions but keeps field results")
    func skipsDestinations() {
        let rtf = #"{\rtf1 Before {\pict\pngblip 89504e47} {\field{\*\fldinst HYPERLINK "https://x.y"}{\fldrslt Link}} after}"#
        #expect(RTFTextExtractor.plainText(from: Data(rtf.utf8)) == "Before  Link after")
    }

    @Test("Reads text from HTML, skipping markup, scripts and comments")
    func readsHTML() {
        let html = """
        <html><head><meta charset="utf-8"><style>p { color: red; }</style></head>
        <body><!-- note --><p>Hello&nbsp;<b>bold</b> &amp; <i>caf&eacute;</i></p>
        <script>alert("x")</script><ul><li>One</li><li>Two &#x1F44B; &#233;</li></ul></body></html>
        """
        #expect(HTMLTextExtractor.plainText(from: html) == "Hello\u{00A0}bold & caf&eacute;\nOne\nTwo 👋 é")
    }

    @Test("Treats a stray angle bracket and ampersand as text")
    func keepsStrayCharacters() {
        #expect(HTMLTextExtractor.plainText(from: "a < b & c") == "a < b & c")
        #expect(HTMLTextExtractor.plainText(from: "1 < 2 and 3 > 2") == "1 < 2 and 3 > 2")
        // As in a browser, "<y" opens a tag that runs to the next ">".
        #expect(HTMLTextExtractor.plainText(from: "x<y and <b>bold</b>") == "xbold")
        #expect(HTMLTextExtractor.plainText(from: "x<y z") == "x<y z")
    }

    @Test("Handles unclosed comments, tags and skipped elements")
    func handlesUnclosedMarkup() {
        #expect(HTMLTextExtractor.plainText(from: "before<!-- never closed <p>hidden") == "before")
        #expect(HTMLTextExtractor.plainText(from: "before<SCRIPT>alert(1)") == "before")
        #expect(HTMLTextExtractor.plainText(from: "a<script>x</script b") == "a")
        #expect(HTMLTextExtractor.plainText(from: "a<Style>p{}</STYLE>b") == "ab")
        #expect(HTMLTextExtractor.plainText(from: "&#x110000; &#99999999999; &bogus; &amp") == "&#x110000; &#99999999999; &bogus; &amp")
    }

    @Test("Extracts hostile HTML in near-linear time", arguments: [
        "x<y ", "<", "<a", "<!--", "<script>", "</", "&#", "<p>a</p>",
    ])
    func extractsHostileHTMLQuickly(unit: String) {
        let small = String(repeating: unit, count: 50_000)
        let large = String(repeating: unit, count: 400_000)
        let clock = ContinuousClock()
        _ = HTMLTextExtractor.plainText(from: small)  // warm up
        let smallTime = clock.measure { _ = HTMLTextExtractor.plainText(from: small) }
        let largeTime = clock.measure { _ = HTMLTextExtractor.plainText(from: large) }
        // 8x the input may take ~8x the time; quadratic would take ~64x.
        #expect(largeTime < smallTime * 24 + .milliseconds(200), "\(unit): \(smallTime) → \(largeTime)")
        #expect(largeTime < .seconds(5))
    }

    @Test("Extracts a multi-megabyte single line")
    func extractsLongLine() {
        let html = "<p>" + String(repeating: "word ", count: 600_000) + "</p>"
        let elapsed = ContinuousClock().measure {
            #expect(HTMLTextExtractor.plainText(from: html).utf8.count == 600_000 * 5 - 1)
        }
        #expect(elapsed < .seconds(5))
    }

    @Test("Survives deep nesting, unclosed groups and overlong control words in RTF")
    func handlesHostileRTF() {
        let deep = #"{\rtf1 "# + String(repeating: "{", count: 100_000) + "deep" + String(repeating: "}", count: 100_000) + " end}"
        #expect(RTFTextExtractor.plainText(from: Data(deep.utf8)) == "deep end")

        let unclosed = #"{\rtf1 Hello {\b world"#
        #expect(RTFTextExtractor.plainText(from: Data(unclosed.utf8)) == "Hello world")

        let longWord = #"{\rtf1 A\"# + String(repeating: "x", count: 100_000) + #"123456789012345 B}"#
        #expect(RTFTextExtractor.plainText(from: Data(longWord.utf8)) == "AB")

        // `\bin` data may hold braces and backslashes; it is skipped whole.
        let binary = #"{\rtf1 A{\*\blipuid x}\bin5 {}\\\ B}"#
        #expect(RTFTextExtractor.plainText(from: Data(binary.utf8)) == "A B")
    }

    @Test("Extracts hostile RTF in near-linear time", arguments: ["{", "}", "{\\*", "\\u", "\\'", "\\uc9999 "])
    func extractsHostileRTFQuickly(unit: String) {
        let small = Data((#"{\rtf1 "# + String(repeating: unit, count: 50_000)).utf8)
        let large = Data((#"{\rtf1 "# + String(repeating: unit, count: 400_000)).utf8)
        let clock = ContinuousClock()
        _ = RTFTextExtractor.plainText(from: small)
        let smallTime = clock.measure { _ = RTFTextExtractor.plainText(from: small) }
        let largeTime = clock.measure { _ = RTFTextExtractor.plainText(from: large) }
        #expect(largeTime < smallTime * 24 + .milliseconds(200), "\(unit): \(smallTime) → \(largeTime)")
        #expect(largeTime < .seconds(5))
    }
}
