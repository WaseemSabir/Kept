import Foundation

/// A clip's representations as the history stores them, found but not read
/// yet: what `HistoryStore.storedRepresentations(for:types:)` returns.
///
/// Small payloads come along from the database; large ones are blob files
/// that `load()` reads. It holds no database connection, so `load()` can
/// run anywhere: the preview and the thumbnails read big clips off the main
/// actor this way. If the clip is deleted in the meantime, `load()` throws
/// `.missingBlob`.
public struct StoredRepresentations: Sendable {
    struct Entry: Sendable, Hashable {
        let itemIndex: Int
        let type: PasteboardType
        /// The payload's length in bytes.
        let size: Int
        let inlineData: Data?
        let blobHash: String?
    }

    /// In item order, and within an item in the order captured.
    let entries: [Entry]
    let blobs: BlobStore

    public var isEmpty: Bool { entries.isEmpty }

    /// Total bytes across the entries.
    public var byteSize: Int { entries.reduce(0) { $0 + $1.size } }

    /// Whether `load()` reads no files: every payload came from the database.
    public var isInMemory: Bool { entries.allSatisfy { $0.inlineData != nil } }

    /// Only the first entry of the first type in `types` that has one, so
    /// `load()` reads a single representation.
    public func first(ofAny types: [PasteboardType]) -> StoredRepresentations {
        for type in types {
            if let entry = entries.first(where: { $0.type == type }) {
                return StoredRepresentations(entries: [entry], blobs: blobs)
            }
        }
        return StoredRepresentations(entries: [], blobs: blobs)
    }

    /// Every entry's bytes, as pasteboard items in order. Items with none of
    /// the entries are left out.
    public func load() throws(HistoryStoreError) -> [PasteboardItem] {
        var items: [PasteboardItem] = []
        var currentItemIndex: Int?
        for entry in entries {
            let data: Data
            if let inline = entry.inlineData {
                data = inline
            } else if let hash = entry.blobHash {
                data = try blobs.read(hash)
            } else {
                throw .corruptRecord("A representation has no data.")
            }
            if entry.itemIndex != currentItemIndex {
                items.append(PasteboardItem([]))
                currentItemIndex = entry.itemIndex
            }
            items[items.count - 1].representations.append(ClipRepresentation(entry.type, data))
        }
        return items
    }
}
