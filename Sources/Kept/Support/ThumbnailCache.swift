import AppKit
import KeptCore

/// Downsampled images of image clips for the list and the preview.
///
/// Decoding happens off the main actor. Views show `cachedImage` at once
/// and `await image(for:maxPixelSize:)` when it's missing.
@MainActor
final class ThumbnailCache {
    /// Longest side of a list thumbnail, in pixels (a 30 × 20 pt slot at 2×, with room).
    static let rowPixelSize = 96
    /// Longest side of a preview image, in pixels.
    static let previewPixelSize = 1200
    private static let capacity = 120

    private struct Key: Hashable {
        let contentHash: String
        let maxPixelSize: Int
    }

    private let store: HistoryStore?
    private var images: [Key: NSImage] = [:]

    init(store: HistoryStore?) {
        self.store = store
    }

    func cachedImage(for clip: Clip, maxPixelSize: Int) -> NSImage? {
        images[Key(contentHash: clip.contentHash, maxPixelSize: maxPixelSize)]
    }

    /// The clip's image scaled to fit `maxPixelSize`, decoding it if needed;
    /// `nil` for clips without a readable image.
    func image(for clip: Clip, maxPixelSize: Int) async -> NSImage? {
        let key = Key(contentHash: clip.contentHash, maxPixelSize: maxPixelSize)
        if let cached = images[key] { return cached }
        guard let data = imageData(for: clip) else { return nil }

        let decoded = await Task.detached(priority: .userInitiated) {
            ImageTranscoder.thumbnail(of: data, maxPixelSize: maxPixelSize)
        }.value
        guard let decoded else { return nil }

        let image = NSImage(cgImage: decoded.cgImage, size: .zero)
        if images.count >= Self.capacity { images.removeAll() }
        images[key] = image
        return image
    }

    /// Decodes every image clip in `clips` at both sizes, so a render that
    /// can't wait for async work (snapshots) finds them cached.
    func preload(_ clips: [Clip]) async {
        for clip in clips where clip.kind == .image {
            _ = await image(for: clip, maxPixelSize: Self.rowPixelSize)
            _ = await image(for: clip, maxPixelSize: Self.previewPixelSize)
        }
    }

    private func imageData(for clip: Clip) -> Data? {
        guard let store, let items = try? store.representations(for: clip.id) else { return nil }
        let preferred = clip.metadata.imageType.map { [$0] } ?? []
        for type in preferred + PasteboardType.images {
            if let data = items.lazy.compactMap({ $0.data(for: type) }).first {
                return data
            }
        }
        return nil
    }
}
