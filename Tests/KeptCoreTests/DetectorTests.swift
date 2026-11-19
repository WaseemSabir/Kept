import Foundation
import Testing
@testable import KeptCore

@Suite("Content detectors")
struct DetectorTests {
    @Test("Recognizes single links and their hosts", arguments: [
        ("https://github.com/kept/issues/12", "github.com"),
        ("  http://User:pw@Example.COM:8080/path?q=1#top \n", "example.com"),
        ("https://[::1]:8080/", "[::1]"),
        ("HTTPS://www.apple.com", "www.apple.com"),
    ])
    func recognizesLinks(text: String, host: String) {
        #expect(LinkDetector.link(in: text)?.host == host)
    }

    @Test("Recognizes mailto links")
    func recognizesMailto() {
        #expect(LinkDetector.link(in: "mailto:hi@kept.app") == LinkDetector.Link(url: "mailto:hi@kept.app", host: nil))
        #expect(LinkDetector.link(in: "mailto:nobody") == nil)
    }

    @Test("Rejects text that isn't exactly one link", arguments: [
        "see https://github.com", "https://a.com https://b.com", "https://", "http:///path",
        "ftp://files.example.com", "github.com", "https://exa mple.com",
    ])
    func rejectsNonLinks(text: String) {
        #expect(LinkDetector.link(in: text) == nil)
    }

    @Test("Parses CSS colors to hex", arguments: [
        ("#FF6A00", "#FF6A00"), ("#ff6a00", "#FF6A00"), ("#f60", "#FF6600"), ("#f608", "#FF660088"),
        ("#FF6A00FF", "#FF6A00"), ("#FF6A0080", "#FF6A0080"), (" rgb(255, 106, 0) ", "#FF6A00"),
        ("rgb(255 106 0 / 50%)", "#FF6A0080"), ("rgba(0,0,0,0.5)", "#00000080"), ("RGB(100%, 0%, 0%)", "#FF0000"),
    ])
    func parsesColors(text: String, hex: String) {
        #expect(ColorParser.hex(from: text) == hex)
    }

    @Test("Accepts short colors that can't be words or issue numbers", arguments: [
        ("#fff", "#FFFFFF"), ("#000", "#000000"), ("#333", "#333333"), ("#0af", "#00AAFF"), ("#0000", "#00000000"),
        ("#ffff", "#FFFFFF"), ("#123456", "#123456"), ("#00000000", "#00000000"), ("rgb(.5, 10.25, 0)", "#010A00"),
    ])
    func parsesShortColors(text: String, hex: String) {
        #expect(ColorParser.hex(from: text) == hex)
    }

    @Test("Rejects things that aren't colors", arguments: [
        "#FF6A0", "#GG0000", "#hashtag", "rgb(256, 0, 0)", "rgb(1, 2)", "rgba(0,0,0,2)", "FF6A00", "#",
        // Issue references and words.
        "#123", "#1234", "#404", "#add", "#bad", "#cafe", "#beef", "#face", "#fade",
        // Fullwidth and other non-ASCII digits.
        "#１２３４５６", "#ＦＦ６Ａ００", "rgb(２５５, 0, 0)", "#١٢٣٤٥٦",
        // Numbers CSS doesn't allow.
        "rgb(0x10, 1e2, 3)", "rgb(+1, 2, 3)", "rgb(-0, 2, 3)", "rgb(1., 2, 3)", "rgb(inf, 0, 0)", "rgb(nan, 0, 0)",
        "rgba(1, 2, 3, 1e-1)",
    ])
    func rejectsNonColors(text: String) {
        #expect(ColorParser.hex(from: text) == nil)
    }

    @Test("Gives up early on long text")
    func detectorsBailOutOnLength() {
        let huge = "#" + String(repeating: "f", count: 5) + String(repeating: " ", count: 10_000_000)
        let url = "https://example.com/" + String(repeating: "a", count: 10_000_000)
        let elapsed = ContinuousClock().measure {
            #expect(ColorParser.hex(from: huge) == nil)
            #expect(LinkDetector.link(in: url) == nil)
        }
        #expect(elapsed < .milliseconds(500))
        let longButFine = "https://Example.com/" + String(repeating: "a", count: 10_000)
        #expect(LinkDetector.link(in: longButFine)?.host == "example.com")
        #expect(LinkDetector.link(in: longButFine)?.url == longButFine)
    }

    @Test("Spots code, paths and JSON", arguments: [
        "func makeBody() {\n    return 1\n}",
        "let x = 5;",
        "{\"name\": \"Kept\", \"version\": 1}",
        "[{\"a\": 1}]",
        "~/Documents/report.pdf",
        "/usr/local/bin/swift",
        "/Users/me/My Documents/report.pdf",
        "if (a == b && c) {\n  call();\n}",
        "def main():\n    print(\"hi\")\n    return 0",
        "SELECT id, title FROM clips WHERE pin_order IS NULL;",
        "C:\\Users\\me",
    ])
    func spotsCode(text: String) {
        #expect(CodeDetector.looksLikeCode(text))
    }

    @Test("Leaves prose alone", arguments: [
        "Meeting notes for Thursday",
        "I think (maybe) we should go.",
        "Hello, world!",
        "Remember to buy milk, eggs and bread.\nAlso call Sam about the trip.",
        "/ is a slash",
        "The function returns early when the list is empty.",
    ])
    func leavesProse(text: String) {
        #expect(!CodeDetector.looksLikeCode(text))
    }

    @Test("Reads a PNG's pixel size")
    func readsPNGSize() {
        let inspector = PNGImageInspector()
        #expect(inspector.pixelSize(of: pngData(width: 1440, height: 900), type: .png) == PixelSize(width: 1440, height: 900))
        #expect(inspector.pixelSize(of: Data([0x89, 0x50]), type: .png) == nil)
        #expect(inspector.pixelSize(of: Data(repeating: 0, count: 64), type: .png) == nil)
    }
}
