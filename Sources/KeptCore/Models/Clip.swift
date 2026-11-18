import Foundation

/// One entry in the history, without its payload.
///
/// `HistoryStore` keeps these in memory so the panel opens instantly; the
/// representations are loaded on demand with `representations(for:)`.
public struct Clip: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let kind: ClipKind
    /// Sanitized single-line summary, at most 1,000 characters.
    public let title: String
    /// Sanitized text to search, at most 8 KB of UTF-8.
    public let searchText: String
    /// Lowercase hex SHA-256 of the primary payload; the dedup key.
    public let contentHash: String
    /// The app the clip was copied from, when known.
    public internal(set) var sourceBundleID: String?
    public let firstCopiedAt: Date
    /// When the clip was last copied or pasted from Kept; orders the history.
    public internal(set) var lastCopiedAt: Date
    /// How many times the same content has been copied.
    public internal(set) var copyCount: Int
    /// Position among the pins (0 first), or `nil` when not pinned.
    public internal(set) var pinOrder: Int?
    /// Total bytes across all stored representations.
    public let byteSize: Int
    public let metadata: ClipMetadata
    /// `searchText` folded for matching, computed once per clip.
    let searchKey: SearchKey

    public var isPinned: Bool { pinOrder != nil }

    public init(
        id: UUID = UUID(),
        kind: ClipKind,
        title: String,
        searchText: String,
        contentHash: String,
        sourceBundleID: String? = nil,
        firstCopiedAt: Date,
        lastCopiedAt: Date,
        copyCount: Int = 1,
        pinOrder: Int? = nil,
        byteSize: Int,
        metadata: ClipMetadata = ClipMetadata()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.searchText = searchText
        self.contentHash = contentHash
        self.sourceBundleID = sourceBundleID
        self.firstCopiedAt = firstCopiedAt
        self.lastCopiedAt = lastCopiedAt
        self.copyCount = copyCount
        self.pinOrder = pinOrder
        self.byteSize = byteSize
        self.metadata = metadata
        self.searchKey = SearchKey(searchText)
    }
}
