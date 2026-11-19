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
    /// The name the user gave the clip (`HistoryStore.rename(_:to:)`):
    /// sanitized, single line, at most `maxCustomTitleCharacters`; `nil`
    /// when it has none.
    public let customTitle: String?
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
    /// The custom title and `searchText`, folded for matching, computed
    /// once per clip.
    let searchKey: SearchKey

    /// The longest custom title kept, in characters.
    public static let maxCustomTitleCharacters = 200

    public var isPinned: Bool { pinOrder != nil }

    /// What the list shows: the custom title when there is one, else the
    /// title worked out from the content.
    public var displayTitle: String { customTitle ?? title }

    public init(
        id: UUID = UUID(),
        kind: ClipKind,
        title: String,
        customTitle: String? = nil,
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
        self.customTitle = customTitle
        self.searchText = searchText
        self.contentHash = contentHash
        self.sourceBundleID = sourceBundleID
        self.firstCopiedAt = firstCopiedAt
        self.lastCopiedAt = lastCopiedAt
        self.copyCount = copyCount
        self.pinOrder = pinOrder
        self.byteSize = byteSize
        self.metadata = metadata
        // A line break keeps the name's last word and the text's first
        // apart, and both start words.
        self.searchKey = SearchKey(customTitle.map { $0 + "\n" + searchText } ?? searchText)
    }

    /// `title` as a custom title: collapsed onto one line, invisible and
    /// layout-stalling characters dropped, cut to
    /// `maxCustomTitleCharacters`. `nil` when nothing visible is left.
    public static func sanitizedCustomTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let sanitized = TextSanitizer.singleLine(title, maxCharacters: maxCustomTitleCharacters)
        return TextSanitizer.hasVisibleContent(sanitized) ? sanitized : nil
    }

    /// This clip with another custom title (already sanitized).
    func withCustomTitle(_ customTitle: String?) -> Clip {
        Clip(
            id: id,
            kind: kind,
            title: title,
            customTitle: customTitle,
            searchText: searchText,
            contentHash: contentHash,
            sourceBundleID: sourceBundleID,
            firstCopiedAt: firstCopiedAt,
            lastCopiedAt: lastCopiedAt,
            copyCount: copyCount,
            pinOrder: pinOrder,
            byteSize: byteSize,
            metadata: metadata
        )
    }
}
