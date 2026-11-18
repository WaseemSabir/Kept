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
    }
}
