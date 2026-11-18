/// What a clip mainly holds, decided once when it's captured.
///
/// Code-like text is `.text` (or `.richText`) with
/// `ClipMetadata.looksLikeCode` set; that only changes how it's drawn.
public enum ClipKind: String, Sendable, Hashable, Codable, CaseIterable {
    case text
    case richText
    case link
    case image
    case file
    case color
}
