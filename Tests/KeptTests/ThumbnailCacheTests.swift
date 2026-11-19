import AppKit
import Testing
@testable import Kept
import KeptCore

@MainActor
@Suite("Thumbnail cache")
struct ThumbnailCacheTests {
    let directory: URL

    init() throws {
        directory = try makeTemporaryDirectory()
    }

    /// An image clip; images of different widths have different bytes.
    private func imageClip(width: Int, in store: HistoryStore, types: [String] = ["public.png"]) throws -> Clip {
        let representations = try types.map { type in
            ClipRepresentation(PasteboardType(type), try encodedImage(width: width, height: 200, type: type))
        }
        let snapshot = PasteboardSnapshot(items: [PasteboardItem(representations)])
        let builder = ClipBuilder(imageInspector: ImageIOInspector())
        return try store.record(try #require(builder.build(from: snapshot)))
    }

    @Test("Decodes a clip's image once and keeps it at the size asked for")
    func decodesAndKeeps() async throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try HistoryStore(directory: directory)
        let clip = try imageClip(width: 300, in: store)
        let cache = ThumbnailCache(store: store)
        let row = ThumbnailCache.rowPixelSize

        #expect(cache.cachedImage(for: clip, maxPixelSize: row) == nil)
        let loaded = await cache.image(for: clip, maxPixelSize: row)
        let image = try #require(loaded)
        #expect(max(image.size.width, image.size.height) <= CGFloat(row))
        #expect(cache.cachedImage(for: clip, maxPixelSize: row) === image)
        #expect(cache.cachedImage(for: clip, maxPixelSize: ThumbnailCache.previewPixelSize) == nil)
        #expect(cache.loadingCount == 0)
        #expect(cache.cachedCost.rows > 0)
        #expect(cache.cachedCost.previews == 0)
    }

    @Test("Keeps thumbnails within their byte limit, least recently used out first")
    func evictsByCost() async throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try HistoryStore(directory: directory)
        let clips = try [300, 350, 400].map { try imageClip(width: $0, in: store) }
        let row = ThumbnailCache.rowPixelSize

        // What each thumbnail costs, measured alone.
        var costs: [Int] = []
        for clip in clips {
            let alone = ThumbnailCache(store: store)
            _ = await alone.image(for: clip, maxPixelSize: row)
            costs.append(alone.cachedCost.rows)
        }

        // Room for the last two only.
        let cache = ThumbnailCache(store: store, rowCostLimit: costs[1] + costs[2])
        for clip in clips {
            let image = await cache.image(for: clip, maxPixelSize: row)
            #expect(image != nil)
        }
        #expect(cache.cachedCount == 2)
        #expect(cache.cachedCost.rows <= costs[1] + costs[2])
        #expect(cache.cachedImage(for: clips[0], maxPixelSize: row) == nil)
        #expect(cache.cachedImage(for: clips[1], maxPixelSize: row) != nil)
        #expect(cache.cachedImage(for: clips[2], maxPixelSize: row) != nil)
    }

    @Test("Reads only the clip's own image type")
    func readsOneRepresentation() async throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try HistoryStore(directory: directory)
        // The uncompressed TIFF is a blob file; the one-color PNG is small.
        let clip = try imageClip(width: 300, in: store, types: ["public.png", "public.tiff"])
        #expect(clip.metadata.imageType == .png)
        let blobs = directory.appendingPathComponent("blobs")
        for name in try FileManager.default.contentsOfDirectory(atPath: blobs.path) {
            try FileManager.default.removeItem(at: blobs.appendingPathComponent(name))
        }

        let image = await ThumbnailCache(store: store).image(for: clip, maxPixelSize: ThumbnailCache.previewPixelSize)
        #expect(image != nil)
    }

    @Test("A cancelled request returns nothing and leaves nothing loading")
    func cancelledRequest() async throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try HistoryStore(directory: directory)
        let clip = try imageClip(width: 300, in: store)
        let cache = ThumbnailCache(store: store)

        let request = Task { await cache.image(for: clip, maxPixelSize: ThumbnailCache.previewPixelSize) != nil }
        request.cancel()
        #expect(await request.value == false)
        #expect(cache.loadingCount == 0)
        #expect(cache.cachedCount == 0)
    }

    @Test("Has nothing for clips without an image, or without a history")
    func noImage() async throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try HistoryStore(directory: directory)
        let text = try store.record(try textDraft("not a picture"))
        let fromText = await ThumbnailCache(store: store).image(for: text, maxPixelSize: 96)
        #expect(fromText == nil)
        let clip = try imageClip(width: 300, in: store)
        let withoutHistory = await ThumbnailCache(store: nil).image(for: clip, maxPixelSize: 96)
        #expect(withoutHistory == nil)
    }
}
