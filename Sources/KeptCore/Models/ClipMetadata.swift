/// Kind-specific facts about a clip, worked out at capture time so rows and
/// the preview can show them without loading the payload.
public struct ClipMetadata: Sendable, Hashable, Codable {
    /// Characters in the full text (text, rich text, link and color clips).
    public var characterCount: Int?
    /// Whether the text reads like code, so it's set in a monospaced font.
    public var looksLikeCode: Bool
    /// The lowercased host of a link clip, e.g. `github.com`.
    public var linkHost: String?
    /// A color clip's value as `#RRGGBB` or `#RRGGBBAA`.
    public var colorHex: String?
    /// The primary image's size, when it could be read.
    public var imagePixelSize: PixelSize?
    /// The primary image's type, e.g. `public.png`.
    public var imageType: PasteboardType?
    /// How many files a file clip holds.
    public var fileCount: Int?

    public init(
        characterCount: Int? = nil,
        looksLikeCode: Bool = false,
        linkHost: String? = nil,
        colorHex: String? = nil,
        imagePixelSize: PixelSize? = nil,
        imageType: PasteboardType? = nil,
        fileCount: Int? = nil
    ) {
        self.characterCount = characterCount
        self.looksLikeCode = looksLikeCode
        self.linkHost = linkHost
        self.colorHex = colorHex
        self.imagePixelSize = imagePixelSize
        self.imageType = imageType
        self.fileCount = fileCount
    }

    // Decoding tolerates missing keys so older rows keep loading as fields are added.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        characterCount = try container.decodeIfPresent(Int.self, forKey: .characterCount)
        looksLikeCode = try container.decodeIfPresent(Bool.self, forKey: .looksLikeCode) ?? false
        linkHost = try container.decodeIfPresent(String.self, forKey: .linkHost)
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)
        imagePixelSize = try container.decodeIfPresent(PixelSize.self, forKey: .imagePixelSize)
        imageType = try container.decodeIfPresent(PasteboardType.self, forKey: .imageType)
        fileCount = try container.decodeIfPresent(Int.self, forKey: .fileCount)
    }
}
