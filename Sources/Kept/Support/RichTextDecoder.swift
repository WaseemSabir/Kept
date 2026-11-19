import AppKit

/// Plain text from rich text, with AppKit's RTF reader.
enum RichTextDecoder {
    static func plainText(fromRTF data: Data) -> String? {
        guard let text = NSAttributedString(rtf: data, documentAttributes: nil)?.string, !text.isEmpty else {
            return nil
        }
        return text
    }
}
