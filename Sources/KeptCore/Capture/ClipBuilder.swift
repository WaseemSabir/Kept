import Foundation

/// Turns a pasteboard snapshot into a `ClipDraft`: keeps only the types Kept
/// stores, enforces the size cap, picks the primary kind, and derives the
/// title, search text, metadata and dedup hash.
///
/// Pure and `Sendable`, so the app can run it off the main actor. It also
/// hashes every representation big enough to become a blob file, so
/// `HistoryStore.record(_:at:)` doesn't hash it again on the main actor.
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
    /// a privacy marker (concealed, transient or auto-generated, in the
    /// items or `declaredTypes`), more than `CapturePolicy.maxItems` items,
    /// no supported types, only whitespace, a disabled kind, or a primary
    /// payload over `settings.maxItemBytes`.
    public func build(from snapshot: PasteboardSnapshot) -> ClipDraft? {
        // Defence in depth: the policy and the reader should have stopped these already.
        guard snapshot.allTypes.allSatisfy({ !CapturePolicy.privacyMarkers.contains($0) }),
              snapshot.items.count <= CapturePolicy.maxItems
        else { return nil }

        let items = supportedItems(of: snapshot.items)
        guard !items.isEmpty else { return nil }
        if !settings.captureFiles, items.contains(where: { $0.data(for: .fileURL) != nil }) {
            return nil
        }
        guard let primary = primaryContent(of: items),
              let cappedItems = capped(items, keeping: primary.payloadTypes)
        else { return nil }

        let hashedItems = withDigests(cappedItems, alwaysHashing: primary.imageType)
        var draft = describe(primary, items: hashedItems)
        draft.sourceBundleID = snapshot.sourceBundleID
        draft.items = hashedItems
        return draft
    }

    /// The draft for text typed into Kept (an edited clip): one item
    /// holding the text as a plain string, described the way a copy of it
    /// would be, whatever its size. `nil` when the text has nothing visible.
    public static func draft(forEditedText text: String) -> ClipDraft? {
        let builder = ClipBuilder(settings: CaptureSettings(maxItemBytes: .max))
        let item = PasteboardItem([ClipRepresentation(.string, string: text)])
        return builder.build(from: PasteboardSnapshot(items: [item]))
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

    /// `items` with the SHA-256 of every representation that will become a
    /// blob file, and of every `alwaysHashing` image (its digest feeds the
    /// content hash), worked out here instead of on the main actor.
    private func withDigests(_ items: [PasteboardItem], alwaysHashing imageType: PasteboardType?) -> [PasteboardItem] {
        items.map { item in
            var item = item
            for index in item.representations.indices {
                let representation = item.representations[index]
                guard representation.sha256 == nil,
                      representation.data.count > HistoryLimits.defaultInlineThreshold || representation.type == imageType
                else { continue }
                item.representations[index].sha256 = SHA256.hexDigest(of: representation.data)
            }
            return item
        }
    }

    // MARK: Kind detection

    private enum PrimaryContent {
        case files([String])
        /// Every item's representation of this type is part of the image clip.
        case images(PasteboardType)
        /// Text and the type it was read from.
        case text(String, source: PasteboardType)

        /// Types that carry the primary payload and are never dropped to fit the cap.
        var payloadTypes: Set<PasteboardType> {
            switch self {
            case .files: [.fileURL]
            case .images(let type): [type]
            case .text(_, .url): [.url, .string]
            case .text(_, let source): [source]
            }
        }

        var imageType: PasteboardType? {
            if case .images(let type) = self { type } else { nil }
        }
    }

    /// Files first, then a visible string, then images, then a URL, then
    /// text extracted from HTML or RTF. A URL loses to an
    /// image because browsers put the image's address next to its pixels.
    private func primaryContent(of items: [PasteboardItem]) -> PrimaryContent? {
        let fileURLs = items.flatMap { item in
            item.representations.filter { $0.type == .fileURL }.compactMap { Self.fileURLString($0.data) }
        }
        if !fileURLs.isEmpty { return .files(fileURLs) }

        if let text = visibleText(of: .string, in: items) {
            return .text(text, source: .string)
        }
        for type in Self.imageTypes where items.contains(where: { $0.data(for: type) != nil }) {
            return .images(type)
        }
        if let text = visibleText(of: .url, in: items) {
            return .text(text, source: .url)
        }

        // Rich text without a usable plain string.
        if let html = items.lazy.compactMap({ $0.data(for: .html) }).first {
            let text = HTMLTextExtractor.plainText(from: html)
            if TextSanitizer.hasVisibleContent(text) { return .text(text, source: .html) }
        }
        if let rtf = items.lazy.compactMap({ $0.data(for: .rtf) }).first {
            let text = RTFTextExtractor.plainText(from: rtf)
            if TextSanitizer.hasVisibleContent(text) { return .text(text, source: .rtf) }
        }
        return nil
    }

    /// The items' strings of `type`, joined by line breaks, if any is visible.
    private func visibleText(of type: PasteboardType, in items: [PasteboardItem]) -> String? {
        let text = items.compactMap { $0.data(for: type) }.map(Self.decodeString).joined(separator: "\n")
        return TextSanitizer.hasVisibleContent(text) ? text : nil
    }

    // MARK: Describing

    /// Kind, title, search text, metadata and hash for the capped `items`;
    /// the caller fills in the items themselves.
    private func describe(_ primary: PrimaryContent, items: [PasteboardItem]) -> ClipDraft {
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

        case .images(let type):
            let payloads = items.compactMap { item in item.representations.first { $0.type == type } }
            let size = payloads.first.flatMap { imageInspector.pixelSize(of: $0.data, type: type) }
            let title = size.map { "Image \($0.width) × \($0.height)" } ?? "Image"
            return ClipDraft(
                kind: .image,
                title: title,
                searchText: title,
                contentHash: Self.imageHash(payloads.map(\.hexDigest)),
                metadata: ClipMetadata(imagePixelSize: size, imageType: type),
                items: []
            )

        case .text(let text, _):
            // Decided from what survived the size cap, so a clip whose RTF was
            // dropped isn't labelled rich text.
            let hasRichText = items.contains { $0.data(for: .rtf) != nil || $0.data(for: .html) != nil }
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
                contentHash: Self.textHash(text),
                metadata: metadata,
                items: []
            )
        }
    }

    // MARK: Hashes

    /// SHA-256 of `value` prefixed with a domain, so text that happens to
    /// spell a file URL never dedups with the file itself.
    private static func hash(domain: String, _ value: String) -> String {
        var hasher = SHA256()
        hasher.update(domain + "\u{0}")
        hasher.update(value)
        return hasher.finalizeHex()
    }

    /// The text's hash after Unicode canonical composition (NFC) and with
    /// every CRLF or CR turned into LF, so the same words copied as NFD or
    /// with Windows line endings dedup. Pasting still uses the original bytes.
    static func textHash(_ text: String) -> String {
        var hasher = SHA256()
        hasher.update("text\u{0}")
        var normalized = text.utf8.allSatisfy({ $0 < 0x80 }) ? text : text.precomposedStringWithCanonicalMapping
        normalized.withUTF8 { bytes in
            var start = 0
            var index = 0
            while index < bytes.count {
                guard bytes[index] == UInt8(ascii: "\r") else {
                    index += 1
                    continue
                }
                hasher.update(UnsafeRawBufferPointer(UnsafeBufferPointer(rebasing: bytes[start..<index])))
                hasher.update("\n")
                index += 1
                if index < bytes.count, bytes[index] == UInt8(ascii: "\n") { index += 1 }
                start = index
            }
            hasher.update(UnsafeRawBufferPointer(UnsafeBufferPointer(rebasing: bytes[start...])))
        }
        return hasher.finalizeHex()
    }

    /// The hash of an image clip: every primary image's SHA-256, in item
    /// order, under an `image` domain. Digests have a fixed length, so the
    /// sequence is unambiguous, and the store reuses them as blob names.
    static func imageHash(_ digests: [String]) -> String {
        var hasher = SHA256()
        hasher.update("image\u{0}")
        for digest in digests {
            hasher.update(digest)
        }
        return hasher.finalizeHex()
    }

    // MARK: Helpers

    private static let capturedTypes = Set(PasteboardType.captured)
    private static let imageTypes = PasteboardType.images

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
