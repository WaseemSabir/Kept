import AppKit
import KeptCore

/// Writes a clip's pasteboard items back to the pasteboard.
///
/// Every write carries Kept's own marker (`PasteboardType.keptOwn`) and, when
/// known, the original app in `org.nspasteboard.source`, so neither Kept nor
/// other clipboard managers record it as a new copy.
@MainActor
struct PasteboardWriter {
    let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Replaces the pasteboard's contents with `items`, one pasteboard item
    /// each (multi-file pastes need separate items). `markers` (privacy
    /// markers such as `.concealed`) go on the first item, so other
    /// clipboard managers skip the write too. Returns the pasteboard's new
    /// change count, or `nil` when nothing was written.
    func write(_ items: [PasteboardItem], sourceBundleID: String?, markers: [PasteboardType] = []) -> Int? {
        let objects = items
            .filter { !$0.representations.isEmpty }
            .map { item -> NSPasteboardItem in
                let object = NSPasteboardItem()
                for representation in item.representations {
                    object.setData(representation.data, forType: Self.nativeType(representation.type))
                }
                return object
            }
        guard let first = objects.first else { return nil }
        // A non-empty value: some pasteboard readers drop empty types.
        for marker in [PasteboardType.keptOwn] + markers {
            first.setString("1", forType: Self.nativeType(marker))
        }
        if let sourceBundleID, !sourceBundleID.isEmpty {
            first.setString(sourceBundleID, forType: Self.nativeType(.source))
        }

        pasteboard.clearContents()
        guard pasteboard.writeObjects(objects) else { return nil }
        return pasteboard.changeCount
    }

    /// What to write for a clip: every representation, or only plain text.
    ///
    /// Plain text keeps each item's string (or its URL, or the text of its
    /// RTF). Clips with no text at all, such as images, are written whole.
    static func payload(of items: [PasteboardItem], plainTextOnly: Bool) -> [PasteboardItem] {
        guard plainTextOnly else { return items }
        let texts = items.compactMap(plainText(of:))
        guard !texts.isEmpty else { return items }
        return texts.map { PasteboardItem([ClipRepresentation(.string, string: $0)]) }
    }

    /// An item's text: its string, else its URL, else the text of its RTF.
    static func plainText(of item: PasteboardItem) -> String? {
        if let data = item.data(for: .string) ?? item.data(for: .url) {
            return String(decoding: data, as: UTF8.self)
        }
        return item.data(for: .rtf).flatMap(RichTextDecoder.plainText(fromRTF:))
    }

    private static func nativeType(_ type: PasteboardType) -> NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(type.rawValue)
    }
}
