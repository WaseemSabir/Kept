import Foundation
import KeptCore

/// Loads a clip's preview from the store.
@MainActor
enum PreviewLoader {
    /// Text beyond this many characters isn't laid out; the pane says so.
    static let maxCharacters = 20_000

    static func preview(of clip: Clip, store: HistoryStore?) -> ClipPreview {
        switch clip.kind {
        case .image:
            return ClipPreview(.image)
        case .color:
            return ClipPreview(.color(hex: clip.metadata.colorHex ?? clip.title, text: clip.title))
        case .link:
            // A link has no whitespace, so its title is the whole URL.
            return ClipPreview(.link(clip.title))
        case .file:
            return loading(clip, from: store) { items in
                let paths = items
                    .compactMap { $0.data(for: .fileURL) }
                    .map { filePath(fromURLData: $0) }
                return ClipPreview(.files(paths))
            }
        case .text, .richText:
            return loading(clip, from: store) { items in
                let text = fullText(of: items) ?? clip.searchText
                return textPreview(text, isCode: clip.metadata.looksLikeCode)
            }
        }
    }

    /// The text shown for `text`: cut at `maxCharacters`, with its line count.
    static func textPreview(_ text: String, isCode: Bool) -> ClipPreview {
        let lineCount = text.reduce(into: 1) { count, character in
            if character.isNewline { count += 1 }
        }
        let shown = String(text.prefix(maxCharacters))
        let total = shown.count < maxCharacters ? nil : text.count
        return ClipPreview(
            .text(shown, isCode: isCode),
            lineCount: lineCount,
            truncatedFrom: total.flatMap { $0 > maxCharacters ? $0 : nil }
        )
    }

    /// Each item's plain string joined by line breaks, else the text of the
    /// first RTF document.
    static func fullText(of items: [PasteboardItem]) -> String? {
        let strings = items.compactMap { $0.data(for: .string) }.map(decode)
        if !strings.isEmpty { return strings.joined(separator: "\n") }
        if let rtf = items.lazy.compactMap({ $0.data(for: .rtf) }).first {
            return RichTextDecoder.plainText(fromRTF: rtf)
        }
        return nil
    }

    static func filePath(fromURLData data: Data) -> String {
        let text = decode(data).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.isFileURL else { return text }
        return url.path
    }

    private static func loading(
        _ clip: Clip,
        from store: HistoryStore?,
        _ makePreview: ([PasteboardItem]) -> ClipPreview
    ) -> ClipPreview {
        guard let store else { return ClipPreview(.unavailable("History isn't available.")) }
        do {
            return makePreview(try store.representations(for: clip.id))
        } catch {
            Log.panel.error("Couldn't load a preview: \(String(describing: error), privacy: .public)")
            return ClipPreview(.unavailable("Kept couldn't load this clip."))
        }
    }

    /// UTF-8 without the trailing NULs some apps add.
    private static func decode(_ data: Data) -> String {
        var text = String(decoding: data, as: UTF8.self)
        while text.hasSuffix("\u{0}") { text.removeLast() }
        return text
    }
}
