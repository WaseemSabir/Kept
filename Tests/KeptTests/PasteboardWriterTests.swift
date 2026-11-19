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

    @Test("Privacy markers go along with the write")
    func writesMarkers() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let items = [PasteboardItem([ClipRepresentation(.string, string: "hunter2")])]

        _ = try #require(PasteboardWriter(pasteboard: pasteboard).write(items, sourceBundleID: nil, markers: [.concealed]))
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        #expect(types.contains(PasteboardType.concealed.rawValue))
        #expect(types.contains(PasteboardType.keptOwn.rawValue))
        #expect(!types.contains(PasteboardType.source.rawValue))
    }
}
