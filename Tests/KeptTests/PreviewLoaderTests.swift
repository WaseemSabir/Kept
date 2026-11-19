import Foundation
import Testing
@testable import Kept
import KeptCore

@MainActor
@Suite("Preview loader")
struct PreviewLoaderTests {
    let directory: URL

    init() throws {
        directory = try makeTemporaryDirectory()
    }

    private func record(_ representations: ClipRepresentation..., in store: HistoryStore) throws -> Clip {
        let snapshot = PasteboardSnapshot(items: [PasteboardItem(representations)])
        return try store.record(try #require(ClipBuilder().build(from: snapshot)))
    }

    private func removeBlobFiles() throws {
        let blobs = directory.appendingPathComponent("blobs")
        for name in try FileManager.default.contentsOfDirectory(atPath: blobs.path) {
            try FileManager.default.removeItem(at: blobs.appendingPathComponent(name))
        }
    }

    @Test("Previews a clip copied as HTML alone by its text")
    func htmlOnly() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try HistoryStore(directory: directory)
        let clip = try record(ClipRepresentation(.html, string: "<p>Hello <b>world</b></p><p>Again</p>"), in: store)

        let preview = PreviewLoader(store: store).preview(for: clip)
        #expect(preview.content == .text("Hello world\nAgain", isCode: false))
        #expect(preview.lineCount == 2)
    }

    @Test("Reads a big clip off the main actor and cuts a huge character down to size")
    func hostileText() async throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try HistoryStore(directory: directory)
        // One character of 100,000 combining marks: 200 KB, so a blob file.
        let zalgo = "a" + String(repeating: "\u{0301}", count: 100_000) + "\nsecond line"
        let clip = try record(ClipRepresentation(.string, string: zalgo), in: store)
        let loader = PreviewLoader(store: store)

        #expect(loader.preview(for: clip).content == .loading)
        let preview = try #require(await loader.load(clip))
        #expect(preview.content == .text("a" + String(repeating: "\u{0301}", count: 8) + "\nsecond line", isCode: false))
        #expect(preview.lineCount == 2)
        #expect(preview.truncatedFrom == nil)
        // Kept for next time.
        #expect(loader.preview(for: clip) == preview)
    }

    @Test("Reads only a text clip's text, not the picture an app put next to it")
    func skipsPictures() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try HistoryStore(directory: directory)
        let clip = try record(
            ClipRepresentation(.string, string: "Quarterly numbers"),
            ClipRepresentation(.png, Data(repeating: 7, count: 200_000)),
            in: store
        )
        try removeBlobFiles()

        let preview = PreviewLoader(store: store).preview(for: clip)
        #expect(preview.content == .text("Quarterly numbers", isCode: false))
    }

    @Test("Says how much of a long text it shows")
    func truncation() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try HistoryStore(directory: directory)
        let clip = try record(ClipRepresentation(.string, string: String(repeating: "word ", count: 6_000)), in: store)

        let preview = PreviewLoader(store: store).preview(for: clip)
        #expect(preview.truncatedFrom == 30_000)
        #expect(preview.shownCharacterCount == PreviewLoader.maxCharacters)
        if case .text(let text, _) = preview.content {
            #expect(text.utf16.count == PreviewLoader.maxCharacters)
        } else {
            Issue.record("Expected text")
        }
    }

    @Test("Sanitizes file paths")
    func sanitizesPaths() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try HistoryStore(directory: directory)
        // A right-to-left override would show "invoiceexe.pdf".
        let clip = try record(ClipRepresentation(.fileURL, string: "file:///Users/me/invoice%E2%80%AEfdp.exe"), in: store)

        let preview = PreviewLoader(store: store).preview(for: clip)
        #expect(preview.content == .files(["/Users/me/invoicefdp.exe"]))
    }

    @Test("A cancelled load returns nothing")
    func cancelledLoad() async throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try HistoryStore(directory: directory)
        let clip = try record(ClipRepresentation(.string, string: String(repeating: "long text ", count: 20_000)), in: store)
        let loader = PreviewLoader(store: store)

        let load = Task { await loader.load(clip) }
        load.cancel()
        #expect(await load.value == nil)
        #expect(loader.preview(for: clip).content == .loading)
    }

    @Test("Shows kinds without stored data at once")
    func immediateKinds() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try HistoryStore(directory: directory)
        let link = try record(ClipRepresentation(.string, string: "https://kept.app/docs"), in: store)
        let color = try record(ClipRepresentation(.string, string: "#FF6A00"), in: store)
        let loader = PreviewLoader(store: store)
        #expect(loader.preview(for: link).content == .link("https://kept.app/docs"))
        #expect(loader.preview(for: color).content == .color(hex: "#FF6A00", text: "#FF6A00"))
        #expect(PreviewLoader(store: nil).preview(for: link).content == .link("https://kept.app/docs"))
    }
}
