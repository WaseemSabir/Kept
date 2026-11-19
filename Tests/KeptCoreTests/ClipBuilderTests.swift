import Foundation
import Testing
@testable import KeptCore

@Suite("Clip builder")
struct ClipBuilderTests {
    let builder = ClipBuilder()

    // MARK: Kinds

    @Test("Builds a text clip")
    func buildsText() throws {
        let draft = try #require(builder.build(from: textSnapshot("Meeting notes\nfor Thursday", source: "com.apple.Notes")))
        #expect(draft.kind == .text)
        #expect(draft.title == "Meeting notes for Thursday")
        #expect(draft.searchText == "Meeting notes for Thursday")
        #expect(draft.sourceBundleID == "com.apple.Notes")
        #expect(draft.metadata.characterCount == 26)
        #expect(draft.metadata.looksLikeCode == false)
        #expect(draft.items == [item((.string, "Meeting notes\nfor Thursday"))])
        #expect(draft.byteSize == 26)
    }

    @Test("Builds a rich text clip when RTF or HTML comes with the string")
    func buildsRichText() throws {
        let snapshot = PasteboardSnapshot(items: [item((.rtf, #"{\rtf1 Hello}"#), (.string, "Hello"))])
        let draft = try #require(builder.build(from: snapshot))
        #expect(draft.kind == .richText)
        #expect(draft.title == "Hello")
        #expect(draft.items[0].types == [.rtf, .string])
    }

    @Test("Builds a link clip with its host")
    func buildsLink() throws {
        let snapshot = PasteboardSnapshot(items: [
            item((.url, "https://github.com/kept/issues/12"), (.string, "https://github.com/kept/issues/12")),
        ])
        let draft = try #require(builder.build(from: snapshot))
        #expect(draft.kind == .link)
        #expect(draft.metadata.linkHost == "github.com")
        #expect(draft.searchText == "https://github.com/kept/issues/12")
    }

    @Test("Reads a link from the URL type when there's no string")
    func buildsLinkFromURLType() throws {
        let draft = try #require(builder.build(from: PasteboardSnapshot(items: [item((.url, "https://kept.app"))])))
        #expect(draft.kind == .link)
        #expect(draft.title == "https://kept.app")
        #expect(draft.contentHash == textDraft("https://kept.app").contentHash)
    }

    @Test("Builds a color clip", arguments: [("#FF6A00", "#FF6A00"), ("rgb(255, 106, 0)", "#FF6A00")])
    func buildsColor(text: String, hex: String) throws {
        let draft = try #require(builder.build(from: textSnapshot(text)))
        #expect(draft.kind == .color)
        #expect(draft.metadata.colorHex == hex)
        #expect(draft.title == text)
    }

    @Test("Flags code-like text")
    func flagsCode() throws {
        let draft = try #require(builder.build(from: textSnapshot("func makeBody() {\n    return 1\n}")))
        #expect(draft.kind == .text)
        #expect(draft.metadata.looksLikeCode)
        #expect(draft.title == "func makeBody() { return 1 }")
    }

    @Test("Builds an image clip with its pixel size")
    func buildsImage() throws {
        let png = pngData(width: 1440, height: 900, byteCount: 500)
        let snapshot = PasteboardSnapshot(items: [PasteboardItem([ClipRepresentation(.png, png)])])
        let draft = try #require(builder.build(from: snapshot))
        #expect(draft.kind == .image)
        #expect(draft.metadata.imagePixelSize == PixelSize(width: 1440, height: 900))
        #expect(draft.metadata.imageType == .png)
        #expect(draft.title == "Image 1440 × 900")
        #expect(draft.contentHash == ClipBuilder.imageHash([SHA256.hexDigest(of: png)]))
        #expect(draft.contentHash != SHA256.hexDigest(of: png))
    }

    @Test("Uses an injected inspector for other image types")
    func usesInjectedInspector() throws {
        struct FixedInspector: ImageInspecting {
            func pixelSize(of data: Data, type: PasteboardType) -> PixelSize? {
                type == .tiff ? PixelSize(width: 3, height: 2) : nil
            }
        }
        let snapshot = PasteboardSnapshot(items: [PasteboardItem([ClipRepresentation(.tiff, Data([1, 2, 3]))])])
        let draft = try #require(ClipBuilder(imageInspector: FixedInspector()).build(from: snapshot))
        #expect(draft.metadata.imagePixelSize == PixelSize(width: 3, height: 2))
        #expect(draft.metadata.imageType == .tiff)
    }

    @Test("Treats an image with a blank string as an image")
    func imageWithBlankString() throws {
        let snapshot = PasteboardSnapshot(items: [PasteboardItem([
            ClipRepresentation(.string, string: " \n"),
            ClipRepresentation(.tiff, Data([1, 2, 3])),
            ClipRepresentation(.png, pngData(width: 2, height: 2)),
        ])])
        let draft = try #require(builder.build(from: snapshot))
        #expect(draft.kind == .image)
        #expect(draft.metadata.imageType == .png)
        #expect(draft.items[0].types == [.string, .tiff, .png])
    }

    @Test("Prefers text when an app adds a picture of it")
    func prefersTextOverImage() throws {
        let snapshot = PasteboardSnapshot(items: [PasteboardItem([
            ClipRepresentation(.string, string: "Q3 revenue"),
            ClipRepresentation(.html, string: "<td>Q3 revenue</td>"),
            ClipRepresentation(.png, pngData(width: 300, height: 40)),
        ])])
        let draft = try #require(builder.build(from: snapshot))
        #expect(draft.kind == .richText)
        #expect(draft.title == "Q3 revenue")
        #expect(draft.items[0].types == [.string, .html, .png])
    }

    @Test("Builds a file clip from one file")
    func buildsSingleFile() throws {
        let snapshot = PasteboardSnapshot(items: [
            item((.fileURL, "file:///Users/me/Documents/Q3%20report.pdf"), (.string, "Q3 report.pdf")),
        ])
        let draft = try #require(builder.build(from: snapshot))
        #expect(draft.kind == .file)
        #expect(draft.title == "Q3 report.pdf")
        #expect(draft.searchText == "/Users/me/Documents/Q3 report.pdf")
        #expect(draft.metadata.fileCount == 1)
    }

    @Test("Builds one file clip from Finder's one-item-per-file pasteboard")
    func buildsMultipleFiles() throws {
        let snapshot = PasteboardSnapshot(items: [
            item((.fileURL, "file:///Users/me/a.png"), (.string, "a.png")),
            item((.fileURL, "file:///Users/me/b.txt"), (.string, "b.txt")),
            item((.fileURL, "file:///Users/me/Projects/"), (.string, "Projects")),
        ])
        let draft = try #require(builder.build(from: snapshot))
        #expect(draft.kind == .file)
        #expect(draft.title == "a.png, b.txt, Projects")
        #expect(draft.searchText == "/Users/me/a.png /Users/me/b.txt /Users/me/Projects")
        #expect(draft.metadata.fileCount == 3)
        #expect(draft.items.count == 3)
        #expect(draft.items.allSatisfy { $0.types == [.fileURL, .string] })
    }

    @Test("Builds rich text from HTML when the string is blank")
    func buildsRichTextFromHTMLOnly() throws {
        let snapshot = PasteboardSnapshot(items: [item((.string, "  "), (.html, "<p>Only <b>rich</b></p>"))])
        let draft = try #require(builder.build(from: snapshot))
        #expect(draft.kind == .richText)
        #expect(draft.title == "Only rich")
    }

    @Test("Builds rich text from RTF alone")
    func buildsRichTextFromRTFOnly() throws {
        let snapshot = PasteboardSnapshot(items: [item((.rtf, #"{\rtf1{\fonttbl\f0 Helvetica;}\f0 Hello\par World}"#))])
        let draft = try #require(builder.build(from: snapshot))
        #expect(draft.kind == .richText)
        #expect(draft.title == "Hello World")
        #expect(draft.contentHash == textDraft("Hello\nWorld").contentHash)
    }

    @Test("Joins the strings of several items")
    func joinsItemStrings() throws {
        let snapshot = PasteboardSnapshot(items: [item((.string, "first")), item((.string, "second"))])
        let draft = try #require(builder.build(from: snapshot))
        #expect(draft.title == "first second")
        #expect(draft.items.count == 2)
    }

    // MARK: Skipping

    @Test("Skips whitespace-only text", arguments: ["", "   ", "\n\t\n", "\u{200B}\u{FEFF}"])
    func skipsBlankText(text: String) {
        #expect(builder.build(from: textSnapshot(text)) == nil)
    }

    @Test("Skips pasteboards with only types Kept doesn't store")
    func skipsUnsupportedTypes() {
        let snapshot = PasteboardSnapshot(items: [item(("com.apple.webarchive", "…"), ("dyn.ah62d4rv4gu8yc6durvwwaznwmuuha2pxsvw0e55bsmwca7d3sbwu", "x"))])
        #expect(builder.build(from: snapshot) == nil)
        #expect(builder.build(from: PasteboardSnapshot(items: [])) == nil)
    }

    @Test("Skips files when file capture is off")
    func skipsFilesWhenDisabled() {
        let noFiles = ClipBuilder(settings: CaptureSettings(captureFiles: false))
        let snapshot = PasteboardSnapshot(items: [item((.fileURL, "file:///a.txt"), (.string, "a.txt"))])
        #expect(noFiles.build(from: snapshot) == nil)
    }

    @Test("Drops images when image capture is off")
    func dropsImagesWhenDisabled() throws {
        let noImages = ClipBuilder(settings: CaptureSettings(captureImages: false))
        let picture = PasteboardSnapshot(items: [PasteboardItem([ClipRepresentation(.png, pngData(width: 1, height: 1))])])
        #expect(noImages.build(from: picture) == nil)

        let office = PasteboardSnapshot(items: [PasteboardItem([
            ClipRepresentation(.string, string: "Cell"),
            ClipRepresentation(.png, pngData(width: 1, height: 1)),
        ])])
        let draft = try #require(noImages.build(from: office))
        #expect(draft.items[0].types == [.string])
    }

    // MARK: Filtering and size caps

    @Test("Keeps only the types Kept stores, first of each, in order")
    func filtersTypes() throws {
        let snapshot = PasteboardSnapshot(items: [PasteboardItem([
            ClipRepresentation("com.microsoft.ole.source", string: "ole"),
            ClipRepresentation(.html, string: "<b>Hi</b>"),
            ClipRepresentation("org.chromium.web-custom-data", string: "x"),
            ClipRepresentation("com.apple.WebKit.custom-pasteboard-data", string: "x"),
            ClipRepresentation("com.apple.webarchive", string: "x"),
            ClipRepresentation("dyn.ah62d4rv4gu8yc6durvwwaznwmuuha2pxsvw0e55bsmwca7d3sbwu", string: "x"),
            ClipRepresentation(.source, string: "com.google.Chrome"),
            ClipRepresentation(.string, string: "Hi"),
            ClipRepresentation(.string, string: "Duplicate"),
        ])])
        let draft = try #require(builder.build(from: snapshot))
        #expect(draft.items == [item((.html, "<b>Hi</b>"), (.string, "Hi"))])
    }

    @Test("Skips a clip whose primary payload is over the cap")
    func skipsOversizedPayload() {
        let small = ClipBuilder(settings: CaptureSettings(maxItemBytes: 100))
        #expect(small.build(from: textSnapshot(String(repeating: "x", count: 101))) == nil)
        #expect(small.build(from: textSnapshot(String(repeating: "x", count: 100))) != nil)

        let picture = PasteboardSnapshot(items: [PasteboardItem([ClipRepresentation(.png, pngData(width: 9, height: 9, byteCount: 200))])])
        #expect(small.build(from: picture) == nil)
    }

    @Test("Drops the heaviest extra representations to fit the cap")
    func dropsHeavyRepresentations() throws {
        let small = ClipBuilder(settings: CaptureSettings(maxItemBytes: 1000))
        let snapshot = PasteboardSnapshot(items: [PasteboardItem([
            ClipRepresentation(.string, string: "Chart title"),
            ClipRepresentation(.rtf, string: #"{\rtf1 Chart title}"#),
            ClipRepresentation(.tiff, Data(repeating: 7, count: 900)),
            ClipRepresentation(.png, pngData(width: 4, height: 4, byteCount: 300)),
        ])])
        let draft = try #require(small.build(from: snapshot))
        #expect(draft.kind == .richText)
        #expect(draft.items[0].types == [.string, .rtf, .png])
        #expect(draft.byteSize <= 1000)
    }

    @Test("Keeps the primary image and drops a heavier duplicate format")
    func keepsPrimaryImage() throws {
        let small = ClipBuilder(settings: CaptureSettings(maxItemBytes: 1000))
        let png = pngData(width: 8, height: 8, byteCount: 600)
        let snapshot = PasteboardSnapshot(items: [PasteboardItem([
            ClipRepresentation(.tiff, Data(repeating: 1, count: 800)),
            ClipRepresentation(.png, png),
        ])])
        let draft = try #require(small.build(from: snapshot))
        #expect(draft.kind == .image)
        #expect(draft.items == [PasteboardItem([ClipRepresentation(.png, png)])])
    }

    // MARK: Text derivation

    @Test("Sanitizes the title onto one line")
    func sanitizesTitle() throws {
        let draft = try #require(builder.build(from: textSnapshot("\n\n  Hello\u{0000}\u{202E}\t\tworld \u{200B}  \n")))
        #expect(draft.title == "Hello world")
    }

    @Test("Caps the title and search text")
    func capsLengths() throws {
        let long = String(repeating: "lorem ipsum ", count: 2000)
        let draft = try #require(builder.build(from: textSnapshot(long)))
        #expect(draft.title.count == ClipBuilder.maxTitleCharacters)
        #expect(draft.searchText.utf8.count <= ClipBuilder.maxSearchTextBytes)
        #expect(draft.searchText.utf8.count > ClipBuilder.maxSearchTextBytes - 16)
        #expect(draft.metadata.characterCount == long.count)
    }

    @Test("Strips a trailing NUL from strings")
    func stripsTrailingNUL() throws {
        let draft = try #require(builder.build(from: textSnapshot("Hello\u{0}")))
        #expect(draft.contentHash == textDraft("Hello").contentHash)
    }

    // MARK: Dedup hashes

    @Test("Gives the same hash to the same text from different apps")
    func hashesTextAcrossApps() throws {
        let plain = try #require(builder.build(from: textSnapshot("Hello", source: "com.apple.Terminal")))
        let rich = try #require(builder.build(from: PasteboardSnapshot(
            items: [item((.rtf, #"{\rtf1\b Hello}"#), (.html, "<b>Hello</b>"), (.string, "Hello"))],
            sourceBundleID: "com.apple.TextEdit"
        )))
        #expect(plain.contentHash == rich.contentHash)
        #expect(plain.kind == .text)
        #expect(rich.kind == .richText)
    }

    @Test("Gives different hashes to different content")
    func hashesDifferentContent() {
        #expect(textDraft("Hello").contentHash != textDraft("hello").contentHash)
        #expect(textDraft("Hello").contentHash != textDraft("Hello ").contentHash)
    }

    @Test("Keeps text and files that spell the same URL apart")
    func separatesTextFromFiles() throws {
        let file = try #require(builder.build(from: PasteboardSnapshot(items: [item((.fileURL, "file:///a.txt"))])))
        #expect(file.contentHash != textDraft("file:///a.txt").contentHash)
    }

    @Test("Hashes files by their URLs, in order")
    func hashesFiles() throws {
        let ab = PasteboardSnapshot(items: [item((.fileURL, "file:///a")), item((.fileURL, "file:///b"))])
        let ba = PasteboardSnapshot(items: [item((.fileURL, "file:///b")), item((.fileURL, "file:///a"))])
        let first = try #require(builder.build(from: ab))
        let again = try #require(builder.build(from: ab))
        let reversed = try #require(builder.build(from: ba))
        #expect(first.contentHash == again.contentHash)
        #expect(first.contentHash != reversed.contentHash)
    }

    @Test("Hashes every image of a multi-image clip, in order")
    func hashesEveryImage() throws {
        let a = pngData(width: 4, height: 4, byteCount: 200, seed: 1)
        let b = pngData(width: 4, height: 4, byteCount: 200, seed: 2)
        let c = pngData(width: 4, height: 4, byteCount: 200, seed: 3)
        func images(_ payloads: Data...) -> PasteboardSnapshot {
            PasteboardSnapshot(items: payloads.map { PasteboardItem([ClipRepresentation(.png, $0)]) })
        }
        let ab = try #require(builder.build(from: images(a, b)))
        let ac = try #require(builder.build(from: images(a, c)))
        let ba = try #require(builder.build(from: images(b, a)))
        let onlyA = try #require(builder.build(from: images(a)))
        #expect(ab.kind == .image)
        #expect(ab.items.count == 2)
        #expect(ab.contentHash == (try #require(builder.build(from: images(a, b)))).contentHash)
        #expect(Set([ab.contentHash, ac.contentHash, ba.contentHash, onlyA.contentHash]).count == 4)
    }

    @Test("Ignores text normalization and line endings when hashing text")
    func hashesNormalizedText() throws {
        let composed = textDraft("Caf\u{00E9}\nau lait")
        let decomposed = textDraft("Cafe\u{0301}\r\nau lait")
        let classicMac = textDraft("Caf\u{00E9}\rau lait")
        #expect(composed.contentHash == decomposed.contentHash)
        #expect(composed.contentHash == classicMac.contentHash)
        #expect(composed.contentHash != textDraft("Cafe\nau lait").contentHash)
        #expect(textDraft("a\r\n\r\nb").contentHash == textDraft("a\n\nb").contentHash)
        // The original bytes are what gets pasted.
        #expect(decomposed.items == [item((.string, "Cafe\u{0301}\r\nau lait"))])
    }

    @Test("Prefers an image over the URL a browser puts next to it")
    func prefersImageOverURL() throws {
        let png = pngData(width: 16, height: 16)
        let snapshot = PasteboardSnapshot(items: [PasteboardItem([
            ClipRepresentation(.url, string: "https://example.com/cat.png"),
            ClipRepresentation(.png, png),
        ])])
        let draft = try #require(builder.build(from: snapshot))
        #expect(draft.kind == .image)
        #expect(draft.items[0].types == [.url, .png])
        // A visible string still wins over the image.
        let withString = PasteboardSnapshot(items: [PasteboardItem([
            ClipRepresentation(.string, string: "Cat"), ClipRepresentation(.png, png),
        ])])
        #expect(try #require(builder.build(from: withString)).kind == .text)
    }

    @Test("Decides rich text from what survives the size cap")
    func richTextAfterCap() throws {
        let small = ClipBuilder(settings: CaptureSettings(maxItemBytes: 100))
        let snapshot = PasteboardSnapshot(items: [PasteboardItem([
            ClipRepresentation(.string, string: "Hello"),
            ClipRepresentation(.rtf, string: #"{\rtf1 "# + String(repeating: "x", count: 200) + "}"),
        ])])
        let draft = try #require(small.build(from: snapshot))
        #expect(draft.items[0].types == [.string])
        #expect(draft.kind == .text)
    }

    @Test("Hashes large representations for the store, off the main actor")
    func precomputesBlobDigests() throws {
        let large = Data(repeating: 7, count: HistoryLimits.defaultInlineThreshold + 1)
        let snapshot = PasteboardSnapshot(items: [PasteboardItem([
            ClipRepresentation(.string, string: "Chart"),
            ClipRepresentation(.tiff, large),
        ])])
        let draft = try #require(builder.build(from: snapshot))
        let representations = draft.items[0].representations
        #expect(representations[0].sha256 == nil)
        #expect(representations[1].sha256 == SHA256.hexDigest(of: large))

        var changed = representations[1]
        changed.data.append(1)
        #expect(changed.sha256 == nil)
        #expect(changed.hexDigest == SHA256.hexDigest(of: changed.data))
    }

    // MARK: Privacy markers

    @Test("Refuses snapshots that carry a privacy marker", arguments: [
        PasteboardType.concealed, .transient, .autoGenerated,
        .onePasswordLegacy, .keeWeb, .transientLegacy, .typeIt4MeClipping, .pasteboardGenerator,
    ])
    func refusesMarkers(marker: PasteboardType) {
        let inItem = PasteboardSnapshot(items: [item((.string, "hunter2"), (marker, ""))])
        #expect(builder.build(from: inItem) == nil)

        // The app reads only captured types, so the marker is only declared.
        let declared = PasteboardSnapshot(items: [item((.string, "hunter2"))], declaredTypes: [.string, marker])
        #expect(builder.build(from: declared) == nil)
    }

    @Test("Builds reader-shaped snapshots without markers")
    func buildsReaderShapedSnapshot() throws {
        let snapshot = PasteboardSnapshot(
            items: [item((.string, "Hello"))],
            sourceBundleID: "com.apple.Safari",
            declaredTypes: [.string, .html, .source, "com.apple.webarchive"]
        )
        #expect(try #require(builder.build(from: snapshot)).title == "Hello")
    }

    // MARK: Hostile input

    @Test("Builds from hostile rich text in near-linear time")
    func buildsHostileRichTextQuickly() throws {
        let hostile = [
            String(repeating: "x<y ", count: 250_000),
            String(repeating: "<script>", count: 100_000),
            String(repeating: "<a", count: 400_000),
            "<!--" + String(repeating: "-", count: 1_000_000),
            String(repeating: "&#x", count: 300_000),
        ]
        for html in hostile {
            let snapshot = PasteboardSnapshot(items: [item((.string, " "), (.html, html))])
            let elapsed = ContinuousClock().measure { _ = builder.build(from: snapshot) }
            #expect(elapsed < .seconds(5), "\(html.prefix(8))… took \(elapsed)")
        }
        let rtf = PasteboardSnapshot(items: [item((.rtf, #"{\rtf1 "# + String(repeating: "{", count: 1_000_000) + "Hi"))])
        let elapsed = ContinuousClock().measure { _ = builder.build(from: rtf) }
        #expect(elapsed < .seconds(5), "deep RTF took \(elapsed)")
    }

    @Test("Keeps a long single-line clip cheap and its title safe")
    func buildsHugeSingleLine() throws {
        let line = String(repeating: "lorem ipsum dolor sit amet ", count: 80_000)  // ~2 MB
        let clock = ContinuousClock()
        var draft: ClipDraft?
        let elapsed = clock.measure { draft = builder.build(from: textSnapshot(line)) }
        let built = try #require(draft)
        #expect(built.title.count == ClipBuilder.maxTitleCharacters)
        #expect(built.kind == .text)
        #expect(elapsed < .seconds(10), "took \(elapsed)")
    }
}
