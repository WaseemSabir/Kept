import AppKit
import KeptCore

/// Downsampled images of image clips for the list and the preview.
///
/// Only the clip's one image representation is read (the type recorded for
/// it), and it's read and decoded off the main actor. Requests for an image
/// that's already loading share that load, and a load no view waits for
/// any more is cancelled. Decoded images are kept up to a total size in
/// bytes, row thumbnails and preview images apart (so big previews never
/// push out the list's thumbnails), least recently used out first.
///
/// Views show `cachedImage` at once and `await image(for:maxPixelSize:)`
/// when it's missing.
@MainActor
final class ThumbnailCache {
    /// Longest side of a list thumbnail, in pixels (a 30 × 20 pt slot at 2×, with room).
    nonisolated static let rowPixelSize = 96
    /// Longest side of a preview image, in pixels.
    nonisolated static let previewPixelSize = 1200
    /// Bytes of decoded row thumbnails kept: about 650 at 96 × 64.
    nonisolated static let rowCostLimit = 16 * 1024 * 1024
    /// Bytes of decoded preview images kept: about 16 at 1200 × 800.
    nonisolated static let previewCostLimit = 64 * 1024 * 1024

    private struct Key: Hashable, Sendable {
        let contentHash: String
        let maxPixelSize: Int
    }

    private let store: HistoryStore?
    private var rows: LRUCache<Key, NSImage>
    private var previews: LRUCache<Key, NSImage>
    private let loads = SharedLoads<Key, DecodedImage>()

    init(
        store: HistoryStore?,
        rowCostLimit: Int = ThumbnailCache.rowCostLimit,
        previewCostLimit: Int = ThumbnailCache.previewCostLimit
    ) {
        self.store = store
        rows = LRUCache(totalCostLimit: rowCostLimit)
        previews = LRUCache(totalCostLimit: previewCostLimit)
    }

    /// Images kept, at both sizes.
    var cachedCount: Int { rows.count + previews.count }
    /// Bytes of decoded row thumbnails and preview images kept.
    var cachedCost: (rows: Int, previews: Int) { (rows.totalCost, previews.totalCost) }
    /// Images being read and decoded.
    var loadingCount: Int { loads.count }

    func cachedImage(for clip: Clip, maxPixelSize: Int) -> NSImage? {
        let key = Key(contentHash: clip.contentHash, maxPixelSize: maxPixelSize)
        return Self.isRowSize(maxPixelSize) ? rows.value(for: key) : previews.value(for: key)
    }

    /// The clip's image scaled to fit `maxPixelSize`, decoding it if needed;
    /// `nil` for clips without a readable image, or when the caller was
    /// cancelled.
    func image(for clip: Clip, maxPixelSize: Int) async -> NSImage? {
        if let cached = cachedImage(for: clip, maxPixelSize: maxPixelSize) { return cached }
        let key = Key(contentHash: clip.contentHash, maxPixelSize: maxPixelSize)
        guard let stored = storedImage(of: clip) else { return nil }

        let decoded = await loads.value(for: key) {
            guard !Task.isCancelled,
                  let data = try? stored.load().first?.representations.first?.data,
                  !Task.isCancelled
            else { return nil }
            return ImageTranscoder.thumbnail(of: data, maxPixelSize: maxPixelSize)
        }
        guard let decoded else { return nil }

        let image = NSImage(cgImage: decoded.cgImage, size: .zero)
        let cost = decoded.cgImage.bytesPerRow * decoded.cgImage.height
        if Self.isRowSize(maxPixelSize) {
            rows.insert(image, for: key, cost: cost)
        } else {
            previews.insert(image, for: key, cost: cost)
        }
        return image
    }

    /// The clip's one image representation, found but not read: the type
    /// recorded for the clip, else the first image type it has.
    private func storedImage(of clip: Clip) -> StoredRepresentations? {
        guard let store,
              let stored = try? store.storedRepresentations(for: clip.id, types: Set(PasteboardType.images))
        else { return nil }
        let preferred = clip.metadata.imageType.map { [$0] } ?? []
        let image = stored.first(ofAny: preferred + PasteboardType.images)
        return image.isEmpty ? nil : image
    }

    private static func isRowSize(_ maxPixelSize: Int) -> Bool {
        maxPixelSize <= rowPixelSize
    }
}
