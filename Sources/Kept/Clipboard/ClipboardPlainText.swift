import AppKit
import KeptCore

/// Reads what's on the pasteboard now as plain text, for the global "paste
/// clipboard as plain text" shortcut.
///
/// Each item keeps its text (`PasteboardItem.plainText`: string, else URL,
/// else the text of its RTF or HTML, as `PasteboardWriter` does for a
/// clip). Privacy markers and the source
/// app come along, so a password pasted as plain text is still one that
/// other clipboard managers skip.
@MainActor
enum ClipboardPlainText {
    struct Conversion: Equatable {
        /// One string-only item per item that had text.
        var items: [PasteboardItem]
        var sourceBundleID: String?
        /// The privacy markers the pasteboard carried.
        var markers: [PasteboardType]
    }

    /// The pasteboard's text, or `nil` when it holds none (an image, say).
    static func read(from pasteboard: NSPasteboard) -> Conversion? {
        let texts = (pasteboard.pasteboardItems ?? []).compactMap { item -> String? in
            let offered = Set(item.types.map { PasteboardType(rawValue: $0.rawValue) })
            let representations = PasteboardItem.textTypes.filter(offered.contains).compactMap { type in
                item.data(forType: nativeType(type)).map { ClipRepresentation(type, $0) }
            }
            return PasteboardItem(representations).plainText
        }
        guard !texts.isEmpty else { return nil }

        let types = Set((pasteboard.types ?? []).map { PasteboardType(rawValue: $0.rawValue) })
        let source = types.contains(.source) ? pasteboard.string(forType: nativeType(.source)) : nil
        return Conversion(
            items: texts.map { PasteboardItem([ClipRepresentation(.string, string: $0)]) },
            sourceBundleID: source,
            // Remote-clipboard and Kept's own marker don't carry over.
            markers: CapturePolicy.privacyMarkers.filter { types.contains($0) }
        )
    }

    private static func nativeType(_ type: PasteboardType) -> NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(type.rawValue)
    }
}
