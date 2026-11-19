import Foundation

/// One pasteboard type of a clip and its bytes, e.g. `public.rtf` and the
/// RTF document.
public struct ClipRepresentation: Sendable, Hashable {
    public var type: PasteboardType
    public var data: Data {
        didSet { sha256 = nil }
    }

    /// The SHA-256 of `data` (lowercase hex) when `ClipBuilder` already
    /// worked it out off the main actor, so `HistoryStore` can name the blob
    /// file without hashing again. Cleared whenever `data` changes; not part
    /// of equality.
    var sha256: String?

    public init(_ type: PasteboardType, _ data: Data) {
        self.type = type
        self.data = data
    }

    /// A representation holding `string` as UTF-8.
    public init(_ type: PasteboardType, string: String) {
        self.init(type, Data(string.utf8))
    }

    /// The hex SHA-256 of `data`, reusing the cached one when present.
    var hexDigest: String {
        sha256 ?? SHA256.hexDigest(of: data)
    }

    public static func == (lhs: ClipRepresentation, rhs: ClipRepresentation) -> Bool {
        lhs.type == rhs.type && lhs.data == rhs.data
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(type)
        hasher.combine(data)
    }
}
