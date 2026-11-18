import Foundation

/// Turns a pasteboard snapshot into a `ClipDraft`: keeps only the types Kept
/// stores, enforces the size cap, picks the primary kind, and derives the
/// title, search text, metadata and dedup hash.
///
/// Pure and `Sendable`, so the app can run it off the main actor.
public struct ClipBuilder: Sendable {
    public var settings: CaptureSettings
    public var imageInspector: any ImageInspecting

    public static let maxTitleCharacters = 1000
    public static let maxSearchTextBytes = 8 * 1024

    public init(
        settings: CaptureSettings = CaptureSettings(),
        imageInspector: any ImageInspecting = PNGImageInspector()
    ) {
        self.settings = settings
        self.imageInspector = imageInspector
    }

    /// The draft for `snapshot`, or `nil` when there's nothing worth keeping:
    /// no supported types, only whitespace, a disabled kind, or a primary
    /// payload over `settings.maxItemBytes`.
    public func build(from snapshot: PasteboardSnapshot) -> ClipDraft? {
        let items = supportedItems(of: snapshot.items)
        guard !items.isEmpty else { return nil }
        if !settings.captureFiles, items.contains(where: { $0.data(for: .fileURL) != nil }) {
            return nil
        }
        guard let primary = primaryContent(of: items),
              let cappedItems = capped(items, keeping: primary.payloadTypes)
        else { return nil }

        var draft = describe(primary)
        draft.sourceBundleID = snapshot.sourceBundleID
        draft.items = cappedItems
        return draft
    }

    // MARK: Filtering

    /// Each item's supported representations (first of each type, in order),
    /// dropping items left empty.
    private func supportedItems(of items: [PasteboardItem]) -> [PasteboardItem] {
        items.compactMap { item in
            var seen = Set<PasteboardType>()
            let kept = item.representations.filter { representation in
                guard Self.capturedTypes.contains(representation.type) else { return false }
                if !settings.captureImages, Self.imageTypes.contains(representation.type) { return false }
                return seen.insert(representation.type).inserted
            }
            return kept.isEmpty ? nil : PasteboardItem(kept)
        }
    }

    /// Drops the largest non-primary representations until the clip fits
    /// the size cap; `nil` when the primary payload alone doesn't fit.
    private func capped(_ items: [PasteboardItem], keeping payloadTypes: Set<PasteboardType>) -> [PasteboardItem]? {
        var total = items.reduce(0) { $0 + $1.byteSize }
        guard total > settings.maxItemBytes else { return items }

        var droppable: [(item: Int, representation: Int, size: Int)] = []
        for (itemIndex, item) in items.enumerated() {
            for (index, representation) in item.representations.enumerated()
            where !payloadTypes.contains(representation.type) {
                droppable.append((itemIndex, index, representation.data.count))
            }
        }
        var dropped = Set<[Int]>()
        for candidate in droppable.sorted(by: { $0.size > $1.size }) where total > settings.maxItemBytes {
            dropped.insert([candidate.item, candidate.representation])
            total -= candidate.size
        }
        guard total <= settings.maxItemBytes else { return nil }

        return items.enumerated().compactMap { itemIndex, item in
            let kept = item.representations.enumerated()
                .filter { !dropped.contains([itemIndex, $0.offset]) }
                .map(\.element)
            return kept.isEmpty ? nil : PasteboardItem(kept)
        }
    }

    // MARK: Kind detection

    private enum PrimaryContent {
        case files([String])
        case image(type: PasteboardType, data: Data)
        /// Text, the type it was read from, and whether RTF or HTML came with it.
        case text(String, source: PasteboardType, hasRichText: Bool)

        /// Types that carry the primary payload and are never dropped to fit the cap.
        var payloadTypes: Set<PasteboardType> {
            switch self {
            case .files: [.fileURL]
            case .image(let type, _): [type]
            case .text(_, .url, _): [.url, .string]
            case .text(_, let source, _): [source]
            }
        }
    }

    private func primaryContent(of items: [PasteboardItem]) -> PrimaryContent? {
        let fileURLs = items.flatMap { item in
            item.representations.filter { $0.type == .fileURL }.compactMap { Self.fileURLString($0.data) }
        }
        if !fileURLs.isEmpty { return .files(fileURLs) }

        let hasRichText = items.contains { $0.data(for: .rtf) != nil || $0.data(for: .html) != nil }
        for source in [PasteboardType.string, .url] {
            let text = items.compactMap { $0.data(for: source) }.map(Self.decodeString).joined(separator: "\n")
            if TextSanitizer.hasVisibleContent(text) {
                return .text(text, source: source, hasRichText: hasRichText)
            }
        }

        for type in Self.imageTypes {
            if let data = items.lazy.compactMap({ $0.data(for: type) }).first {
                return .image(type: type, data: data)
            }
        }

        // Rich text without a usable plain string.
        if let html = items.lazy.compactMap({ $0.data(for: .html) }).first {
            let text = HTMLTextExtractor.plainText(from: html)
            if TextSanitizer.hasVisibleContent(text) { return .text(text, source: .html, hasRichText: true) }
        }
        if let rtf = items.lazy.compactMap({ $0.data(for: .rtf) }).first {
            let text = RTFTextExtractor.plainText(from: rtf)
            if TextSanitizer.hasVisibleContent(text) { return .text(text, source: .rtf, hasRichText: true) }
        }
        return nil
    }

    // MARK: Describing

    /// Kind, title, search text, metadata and hash; items are filled in by the caller.
    private func describe(_ primary: PrimaryContent) -> ClipDraft {
        switch primary {
        case .files(let urls):
            let paths = urls.map(Self.path(ofFileURL:))
            let names = paths.map { path in
                path.split(separator: "/").last.map(String.init) ?? path
            }
            return ClipDraft(
                kind: .file,
                title: TextSanitizer.singleLine(names.joined(separator: ", "), maxCharacters: Self.maxTitleCharacters),
                searchText: TextSanitizer.searchable(paths.joined(separator: "\n"), maxUTF8Bytes: Self.maxSearchTextBytes),
                contentHash: Self.hash(domain: "files", urls.joined(separator: "\n")),
                metadata: ClipMetadata(fileCount: urls.count),
                items: []
            )

        case .image(let type, let data):
            let size = imageInspector.pixelSize(of: data, type: type)
            let title = size.map { "Image \($0.width) × \($0.height)" } ?? "Image"
            return ClipDraft(
                kind: .image,
                title: title,
                searchText: title,
                contentHash: SHA256.hexDigest(of: data),
                metadata: ClipMetadata(imagePixelSize: size, imageType: type),
                items: []
            )

        case .text(let text, _, let hasRichText):
            var metadata = ClipMetadata(characterCount: text.count)
            let kind: ClipKind
            if let link = LinkDetector.link(in: text) {
                kind = .link
                metadata.linkHost = link.host
            } else if let hex = ColorParser.hex(from: text) {
                kind = .color
                metadata.colorHex = hex
            } else {
                kind = hasRichText ? .richText : .text
                metadata.looksLikeCode = CodeDetector.looksLikeCode(text)
            }
            return ClipDraft(
                kind: kind,
                title: TextSanitizer.singleLine(text, maxCharacters: Self.maxTitleCharacters),
                searchText: TextSanitizer.searchable(text, maxUTF8Bytes: Self.maxSearchTextBytes),
                contentHash: Self.hash(domain: "text", text),
                metadata: metadata,
                items: []
            )
        }
    }

    // MARK: Helpers

    private static let capturedTypes = Set(PasteboardType.captured)
    private static let imageTypes = PasteboardType.images

    /// SHA-256 of `value` prefixed with a domain, so text that happens to
    /// spell a file URL never dedups with the file itself.
    private static func hash(domain: String, _ value: String) -> String {
        var hasher = SHA256()
        hasher.update(domain + "\u{0}")
        hasher.update(value)
        return hasher.finalizeHex()
    }

    /// Pasteboard strings are UTF-8; some apps add a trailing NUL.
    private static func decodeString(_ data: Data) -> String {
        var text = String(decoding: data, as: UTF8.self)
        while text.hasSuffix("\u{0}") { text.removeLast() }
        return text
    }

    private static func fileURLString(_ data: Data) -> String? {
        let text = decodeString(data).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func path(ofFileURL string: String) -> String {
        guard let url = URL(string: string), url.isFileURL else { return string }
        let path = url.path
        return path.isEmpty ? string : path
    }
}
