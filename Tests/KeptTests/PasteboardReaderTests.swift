import AppKit
import Testing
@testable import Kept
import KeptCore

@MainActor
@Suite("Pasteboard reader")
struct PasteboardReaderTests {
    private let reader = PasteboardReader()

    private func read(
        _ pasteboard: NSPasteboard,
        settings: CaptureSettings = CaptureSettings(),
        frontmost: String? = "com.apple.Safari"
    ) -> PasteboardReader.ReadResult {
        reader.read(from: pasteboard, settings: settings, frontmostBundleID: frontmost)
    }

    @Test("Reads the captured types of each item, with the source app")
    func readsSnapshot() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let changeCount = pasteboard.simulateCopy("Hello", markers: [.source])

        guard case .snapshot(let snapshot) = read(pasteboard) else {
            Issue.record("Expected a snapshot")
            return
        }
        #expect(snapshot.changeCount == changeCount)
        // The marker names the source; the frontmost app is only a fallback.
        #expect(snapshot.sourceBundleID == "com.apple.TextEdit")
        #expect(snapshot.items.count == 1)
        #expect(snapshot.items.first?.types == [.string])
        #expect(snapshot.items.first?.data(for: .string) == Data("Hello".utf8))
    }

    @Test("Falls back to the frontmost app")
    func frontmostSource() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.simulateCopy("Hello")
        guard case .snapshot(let snapshot) = read(pasteboard, frontmost: "com.apple.Notes") else {
            Issue.record("Expected a snapshot")
            return
        }
        #expect(snapshot.sourceBundleID == "com.apple.Notes")
    }

    @Test("Marked, own and excluded copies are ignored before reading")
    func ignoresByPolicy() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        pasteboard.simulateCopy("hunter2", markers: [.concealed])
        #expect(read(pasteboard) == .ignored(.concealed))
        pasteboard.simulateCopy("one-time code", markers: [.transient])
        #expect(read(pasteboard) == .ignored(.transient))
        pasteboard.simulateCopy("from Kept", markers: [.keptOwn])
        #expect(read(pasteboard) == .ignored(.ownWrite))

        pasteboard.simulateCopy("from the password app")
        #expect(read(pasteboard, frontmost: "com.apple.Passwords") == .ignored(.excludedApp("com.apple.Passwords")))

        let paused = CaptureSettings(isPaused: true)
        #expect(read(pasteboard, settings: paused) == .ignored(.paused))
    }

    @Test("An excluded app named by the source marker is ignored")
    func excludedByMarker() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("vault item", forType: .string)
        item.setString("com.bitwarden.desktop", forType: NSPasteboard.PasteboardType(PasteboardType.source.rawValue))
        pasteboard.writeObjects([item])
        #expect(read(pasteboard) == .ignored(.excludedApp("com.bitwarden.desktop")))
    }

    @Test("Finder's file reference URLs become path URLs")
    func fileReferenceURLs() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let file = directory.appendingPathComponent("Report 2041.pdf")
        try Data("%PDF".utf8).write(to: file)

        let reference = try #require(CFURLCreateFileReferenceURL(kCFAllocatorDefault, file as CFURL, nil))
        let referenceString = CFURLGetString(reference.takeRetainedValue()) as String
        #expect(referenceString.hasPrefix("file:///.file/id="))

        let resolved = PasteboardReader.resolvingFileReference(Data(referenceString.utf8))
        let url = try #require(URL(string: String(decoding: resolved, as: UTF8.self)))
        #expect(url.isFileURL)
        #expect(url.resolvingSymlinksInPath().path == file.resolvingSymlinksInPath().path)

        // Ordinary path URLs pass through untouched.
        let pathURL = Data(file.absoluteString.utf8)
        #expect(PasteboardReader.resolvingFileReference(pathURL) == pathURL)
    }

    @Test("TIFF-only images are re-encoded as PNG; PNG items are left alone")
    func tiffBecomesPNG() throws {
        let tiff = try encodedImage(width: 4, height: 3, type: "public.tiff")
        let png = try encodedImage(width: 4, height: 3, type: "public.png")
        let snapshot = PasteboardSnapshot(items: [
            PasteboardItem([ClipRepresentation(.tiff, tiff)]),
            PasteboardItem([ClipRepresentation(.png, png), ClipRepresentation(.tiff, tiff)]),
        ])

        let normalized = PasteboardReader.normalized(snapshot)
        #expect(normalized.items[0].types == [.png])
        let converted = try #require(normalized.items[0].data(for: .png))
        #expect(converted.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(ImageIOInspector().pixelSize(of: converted, type: .png) == PixelSize(width: 4, height: 3))
        #expect(normalized.items[1] == snapshot.items[1])
    }

    @Test("ImageIO reads TIFF and JPEG sizes")
    func imageSizes() throws {
        let inspector = ImageIOInspector()
        let tiff = try encodedImage(width: 40, height: 30, type: "public.tiff")
        let jpeg = try encodedImage(width: 16, height: 9, type: "public.jpeg")
        #expect(inspector.pixelSize(of: tiff, type: .tiff) == PixelSize(width: 40, height: 30))
        #expect(inspector.pixelSize(of: jpeg, type: .jpeg) == PixelSize(width: 16, height: 9))
        #expect(inspector.pixelSize(of: Data("not an image".utf8), type: .png) == nil)
    }
}
