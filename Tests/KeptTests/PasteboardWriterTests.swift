import AppKit
import Testing
@testable import Kept
import KeptCore

@MainActor
@Suite("Pasteboard writer")
struct PasteboardWriterTests {
    private static let rtf = #"{\rtf1\ansi Hello, \b world\b0}"#

    @Test("Writes every representation, Kept's marker and the source app")
    func writesEverything() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let writer = PasteboardWriter(pasteboard: pasteboard)
        let items = [PasteboardItem([
            ClipRepresentation(.rtf, string: Self.rtf),
            ClipRepresentation(.string, string: "Hello, world"),
        ])]

        let changeCount = try #require(writer.write(items, sourceBundleID: "com.apple.TextEdit"))
        #expect(changeCount == pasteboard.changeCount)
        #expect(pasteboard.string(forType: .string) == "Hello, world")
        #expect(pasteboard.data(forType: .rtf) == Data(Self.rtf.utf8))
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        #expect(types.contains(PasteboardType.keptOwn.rawValue))
        #expect(pasteboard.string(forType: NSPasteboard.PasteboardType(PasteboardType.source.rawValue)) == "com.apple.TextEdit")

        // Kept never records its own write.
        let read = PasteboardReader().read(from: pasteboard, settings: CaptureSettings(), frontmostBundleID: nil)
        #expect(read == .ignored(.ownWrite))
    }

    @Test("Multiple files go back as one pasteboard item each")
    func multipleFiles() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let paths = ["/Users/sam/Documents/a.pdf", "/Users/sam/Documents/b.png"]
        let items = paths.map { path in
            PasteboardItem([ClipRepresentation(.fileURL, string: URL(fileURLWithPath: path).absoluteString)])
        }

        _ = try #require(PasteboardWriter(pasteboard: pasteboard).write(items, sourceBundleID: nil))
        #expect(pasteboard.pasteboardItems?.count == 2)
        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        #expect(urls?.map(\.path) == paths)
    }

    @Test("Plain text keeps only each item's text")
    func plainTextPayload() {
        let rich = [PasteboardItem([
            ClipRepresentation(.rtf, string: Self.rtf),
            ClipRepresentation(.string, string: "Hello, world"),
        ])]
        #expect(PasteboardWriter.payload(of: rich, plainTextOnly: true) == [
            PasteboardItem([ClipRepresentation(.string, string: "Hello, world")]),
        ])
        #expect(PasteboardWriter.payload(of: rich, plainTextOnly: false) == rich)

        let rtfOnly = [PasteboardItem([ClipRepresentation(.rtf, string: Self.rtf)])]
        #expect(PasteboardWriter.payload(of: rtfOnly, plainTextOnly: true) == [
            PasteboardItem([ClipRepresentation(.string, string: "Hello, world")]),
        ])

        // Nothing textual: written whole.
        let image = [PasteboardItem([ClipRepresentation(.png, Data([0x89, 0x50]))])]
        #expect(PasteboardWriter.payload(of: image, plainTextOnly: true) == image)
    }

    @Test("Copying a clip writes it, tells the monitor and moves the clip to the top")
    func pasteServiceRoundTrip() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let store = try makeStore(in: directory, texts: ["newest", "older"])
        let monitor = PasteboardMonitor(pasteboard: pasteboard, isPaused: { false })
        let service = PasteService(store: store, writer: PasteboardWriter(pasteboard: pasteboard), monitor: monitor)

        let older = try #require(store.recent.last)
        try service.copy(older, asPlainText: false)
        #expect(pasteboard.string(forType: .string) == "older")
        #expect(monitor.poll() == .ownWrite)
        #expect(store.recent.map(\.title) == ["older", "newest"])
    }
}
