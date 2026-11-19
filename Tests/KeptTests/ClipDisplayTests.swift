import Testing
@testable import Kept
import KeptCore

@Suite("Clip display")
struct ClipDisplayTests {
    @Test("Links split into host and the rest, without scheme or www")
    func linkParts() {
        func parts(_ url: String) -> [String] {
            let parts = ClipDisplay.linkParts(of: url)
            return [parts.host, parts.rest]
        }
        #expect(parts("https://github.com/kept/issues/12") == ["github.com", "/kept/issues/12"])
        #expect(parts("http://www.apple.com/") == ["apple.com", ""])
        #expect(parts("https://example.com?q=1") == ["example.com", "?q=1"])
        #expect(parts("mailto:sam@example.com") == ["mailto:sam@example.com", ""])
    }

    @Test("Home folders show as ~")
    func paths() {
        #expect(ClipDisplay.abbreviatedPath("/Users/sam/Documents/report.pdf") == "~/Documents/report.pdf")
        #expect(ClipDisplay.abbreviatedPath("/Applications/Safari.app") == "/Applications/Safari.app")
        #expect(ClipDisplay.folder(of: "/Users/sam/Documents/report.pdf") == "~/Documents")
        #expect(ClipDisplay.folder(of: "report.pdf") == nil)
    }

    @Test("Hex colors give RGBA channels")
    func colors() {
        let orange = ClipDisplay.rgba(fromHex: "#FF6A00")
        #expect(orange?.red == 255 && orange?.green == 106 && orange?.blue == 0 && orange?.alpha == 255)
        let translucent = ClipDisplay.rgba(fromHex: "#3478F680")
        #expect(translucent?.alpha == 128)
        #expect(ClipDisplay.rgba(fromHex: "#XYZ") == nil)
    }

    @Test("Facts for a color list RGB and opacity")
    func colorFacts() {
        let clip = Clip(
            kind: .color, title: "#3478F680", searchText: "#3478F680", contentHash: "h",
            sourceBundleID: "com.apple.Safari", firstCopiedAt: .at(0), lastCopiedAt: .at(0), copyCount: 3,
            byteSize: 9, metadata: ClipMetadata(characterCount: 9, colorHex: "#3478F680")
        )
        let facts = ClipFacts.facts(
            for: clip,
            preview: ClipPreview(.color(hex: "#3478F680", text: "#3478F680")),
            appName: "Safari",
            now: .at(30)
        )
        #expect(facts.map(\.label) == ["From", "Copied", "Times copied", "RGB", "Opacity"])
        #expect(facts.map(\.value) == ["Safari", "Just now", "3", "52, 120, 246", "50%"])
        #expect(facts.first?.appBundleID == "com.apple.Safari")
    }

    @Test("Facts for an image list its dimensions, size and format")
    func imageFacts() {
        let clip = Clip(
            kind: .image, title: "Image 1440 × 900", searchText: "Image 1440 × 900", contentHash: "h",
            firstCopiedAt: .at(0), lastCopiedAt: .at(0), byteSize: 1_200_000,
            metadata: ClipMetadata(imagePixelSize: PixelSize(width: 1440, height: 900), imageType: .png)
        )
        let facts = ClipFacts.facts(for: clip, preview: ClipPreview(.image), appName: nil, now: .at(0))
        #expect(facts.map(\.label) == ["Copied", "Dimensions", "Size", "Format"])
        #expect(facts[1].value == "1440 × 900")
        #expect(facts[3].value == "PNG")
    }

    @Test("Multi-file clips read as a count")
    func fileSummary() {
        let clip = Clip(
            kind: .file, title: "a.pdf, b.png, c.txt", searchText: "", contentHash: "h",
            firstCopiedAt: .at(0), lastCopiedAt: .at(0), byteSize: 10, metadata: ClipMetadata(fileCount: 3)
        )
        #expect(ClipDisplay.fileSummary(of: clip) == "3 files")
        #expect(ClipDisplay.firstFileName(of: clip) == "a.pdf")
    }
}
