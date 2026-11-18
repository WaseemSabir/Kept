/// A clip that has been captured but not stored yet: what `ClipBuilder`
/// produces and `HistoryStore.record(_:at:)` consumes.
public struct ClipDraft: Sendable, Hashable {
    public var kind: ClipKind
    /// Sanitized single-line summary, at most 1,000 characters.
    public var title: String
    /// Sanitized text to search, at most 8 KB of UTF-8.
    public var searchText: String
    /// Lowercase hex SHA-256 of the primary payload; the dedup key.
    public var contentHash: String
    public var sourceBundleID: String?
    public var metadata: ClipMetadata
    /// Every captured pasteboard item, in order, for a faithful paste.
    public var items: [PasteboardItem]

    public init(
        kind: ClipKind,
        title: String,
        searchText: String,
        contentHash: String,
        sourceBundleID: String? = nil,
        metadata: ClipMetadata = ClipMetadata(),
        items: [PasteboardItem]
    ) {
        self.kind = kind
        self.title = title
        self.searchText = searchText
        self.contentHash = contentHash
        self.sourceBundleID = sourceBundleID
        self.metadata = metadata
        self.items = items
    }

    /// Total bytes across all representations.
    public var byteSize: Int {
        items.reduce(0) { $0 + $1.byteSize }
    }
}
