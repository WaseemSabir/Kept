import Foundation

/// One item on the pasteboard: its representations in the order the source
/// app offered them, richest first.
///
/// Most copies have one item; Finder writes one item per file.
public struct PasteboardItem: Sendable, Hashable {
    public var representations: [ClipRepresentation]

    public init(_ representations: [ClipRepresentation]) {
        self.representations = representations
    }

    public var types: [PasteboardType] {
        representations.map(\.type)
    }

    /// The bytes of the first representation of `type`.
    public func data(for type: PasteboardType) -> Data? {
        representations.first { $0.type == type }?.data
    }

    /// Total bytes across all representations.
    public var byteSize: Int {
        representations.reduce(0) { $0 + $1.data.count }
    }

    // MARK: Plain text

    /// The types `plainText` reads, in the order it tries them.
    public static let textTypes: [PasteboardType] = [.string, .url, .rtf, .html]

    /// The item's text, for pasting as plain text and for the preview: its
    /// string, else its URL, else the text of its RTF, else of its HTML (the
    /// first with anything visible in it; RTF and HTML through the core
    /// extractors, which are linear on hostile input). A string that is
    /// only whitespace still counts when nothing else has text. `nil` when
    /// the item has no text at all, such as an image.
    public var plainText: String? {
        var whitespaceOnly: String?
        for type in Self.textTypes {
            guard let data = data(for: type) else { continue }
            let text: String
            switch type {
            case .rtf: text = RTFTextExtractor.plainText(from: data)
            case .html: text = HTMLTextExtractor.plainText(from: data)
            default: text = Self.decodeString(data)
            }
            if TextSanitizer.hasVisibleContent(text) { return text }
            if type == .string, !text.isEmpty { whitespaceOnly = text }
        }
        return whitespaceOnly
    }

    /// Every item's `plainText`, joined by line breaks; `nil` when none has
    /// any.
    public static func plainText(of items: [PasteboardItem]) -> String? {
        let texts = items.compactMap(\.plainText)
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    /// Pasteboard strings are UTF-8; some apps add a trailing NUL.
    private static func decodeString(_ data: Data) -> String {
        var text = String(decoding: data, as: UTF8.self)
        while text.hasSuffix("\u{0}") { text.removeLast() }
        return text
    }
}
