import Foundation

/// Pulls the visible text out of an HTML fragment without a web view.
///
/// Good enough for titles, search and dedup of clips that carry HTML but no
/// plain string; pasting always uses the original bytes. Tags are dropped,
/// block elements become line breaks, `script`/`style`/`head` content and
/// comments are skipped, and common character references are decoded.
///
/// Works on UTF-8 bytes (all markup is ASCII) in one linear pass: every
/// search for a closing `>`, `-->` or end tag either moves past what it
/// found or ends the scan, so hostile input such as thousands of lone `<`
/// can't make it quadratic.
enum HTMLTextExtractor {
    static func plainText(from data: Data) -> String {
        data.withUnsafeBytes { plainText(utf8: $0) }
    }

    static func plainText(from html: String) -> String {
        var html = html
        return html.withUTF8 { plainText(utf8: UnsafeRawBufferPointer($0)) }
    }

    private static func plainText(utf8 bytes: UnsafeRawBufferPointer) -> String {
        var scanner = Scanner(bytes: bytes)
        scanner.run()
        return String(decoding: tidy(scanner.output), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Scanner {
        let bytes: UnsafeRawBufferPointer
        var output: [UInt8] = []
        /// The last `>` in the document; a `<` after it can't open a tag.
        let lastClose: Int?

        init(bytes: UnsafeRawBufferPointer) {
            self.bytes = bytes
            lastClose = bytes.lastIndex(of: Byte.greaterThan)
            output.reserveCapacity(min(bytes.count, 1 << 20))
        }

        mutating func run() {
            var index = 0
            while index < bytes.count {
                // Copy the run of plain text up to the next byte that needs attention.
                var end = index
                while end < bytes.count, !Byte.isSpecial(bytes[end]) { end += 1 }
                if end > index {
                    output.append(contentsOf: bytes[index..<end])
                    index = end
                    continue
                }
                switch bytes[index] {
                case Byte.lessThan:
                    index = skipMarkup(from: index)
                case Byte.ampersand:
                    index = decodeReference(from: index)
                default:  // Line breaks and tabs are spacing in HTML.
                    output.append(Byte.space)
                    index += 1
                }
            }
        }

        /// Consumes a tag, comment or skipped element starting at `start` (a
        /// `<`), and returns the index just past it.
        private mutating func skipMarkup(from start: Int) -> Int {
            if matches("<!--", at: start) {
                return firstIndex(of: "-->", from: start + 4).map { $0 + 3 } ?? bytes.count
            }
            // As in browsers, `<` opens a tag only before a letter, `/`, `!` or `?`.
            let next = start + 1 < bytes.count ? bytes[start + 1] : 0
            let opensTag = Byte.isLetter(next) || next == Byte.slash || next == Byte.bang || next == Byte.question
            guard opensTag, let lastClose, lastClose > start,
                  let end = bytes[(start + 1)...lastClose].firstIndex(of: Byte.greaterThan)
            else {
                output.append(Byte.lessThan)
                return start + 1
            }

            let isClosing = next == Byte.slash
            let name = tagName(from: start + 1, to: end)
            if !isClosing, HTMLTextExtractor.skippedElements.contains(name) {
                guard let closeStart = firstIndex(of: "</" + name, from: end + 1, caseInsensitive: true),
                      let lastClose = self.lastClose, lastClose >= closeStart,
                      let closeEnd = bytes[closeStart...lastClose].firstIndex(of: Byte.greaterThan)
                else { return bytes.count }
                return closeEnd + 1
            }
            if HTMLTextExtractor.lineBreakElements.contains(name) {
                output.append(Byte.newline)
            } else if name == "td" || name == "th" {
                output.append(Byte.tab)
            }
            return end + 1
        }

        /// The tag's name, lowercased: ASCII letters and digits after `<` or
        /// `</`, at most 16 (no element Kept cares about is longer).
        private func tagName(from start: Int, to end: Int) -> String {
            var index = start
            while index < end, bytes[index] == Byte.slash { index += 1 }
            var name: [UInt8] = []
            while index < end, name.count < 16, Byte.isLetter(bytes[index]) || Byte.isDigit(bytes[index]) {
                name.append(Byte.lowercased(bytes[index]))
                index += 1
            }
            return String(decoding: name, as: UTF8.self)
        }

        /// Decodes `&name;`, `&#123;` or `&#x1F600;` at `start`, or copies the
        /// ampersand when it isn't a reference Kept knows.
        private mutating func decodeReference(from start: Int) -> Int {
            let limit = min(bytes.count, start + 12)
            guard let semicolon = bytes[start..<limit].firstIndex(of: Byte.semicolon) else {
                output.append(Byte.ampersand)
                return start + 1
            }
            let body = bytes[(start + 1)..<semicolon]
            var value: UInt32?
            if body.first == Byte.hash {
                let digits = body.dropFirst()
                if let marker = digits.first, marker == UInt8(ascii: "x") || marker == UInt8(ascii: "X") {
                    value = number(digits.dropFirst(), radix: 16)
                } else {
                    value = number(digits, radix: 10)
                }
            } else {
                value = HTMLTextExtractor.namedReferences[String(decoding: body, as: UTF8.self)]
            }
            guard let value, let scalar = Unicode.Scalar(value) else {
                output.append(Byte.ampersand)
                return start + 1
            }
            UTF8.encode(scalar) { output.append($0) }
            return semicolon + 1
        }

        private func number(_ digits: Slice<UnsafeRawBufferPointer>, radix: UInt32) -> UInt32? {
            guard !digits.isEmpty else { return nil }
            var value: UInt32 = 0
            for byte in digits {
                let digit: UInt32
                switch byte {
                case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(byte - UInt8(ascii: "0"))
                case UInt8(ascii: "a")...UInt8(ascii: "f") where radix == 16: digit = UInt32(byte - UInt8(ascii: "a") + 10)
                case UInt8(ascii: "A")...UInt8(ascii: "F") where radix == 16: digit = UInt32(byte - UInt8(ascii: "A") + 10)
                default: return nil
                }
                value = value * radix + digit
                if value > 0x10FFFF { return nil }
            }
            return value
        }

        private func matches(_ pattern: String, at index: Int, caseInsensitive: Bool = false) -> Bool {
            var position = index
            for expected in pattern.utf8 {
                guard position < bytes.count else { return false }
                let actual = bytes[position]
                let equal = caseInsensitive ? Byte.lowercased(actual) == Byte.lowercased(expected) : actual == expected
                guard equal else { return false }
                position += 1
            }
            return true
        }

        /// Where `pattern` (a few ASCII bytes) next starts at or after `start`.
        private func firstIndex(of pattern: String, from start: Int, caseInsensitive: Bool = false) -> Int? {
            guard let first = pattern.utf8.first else { return nil }
            let firstLower = Byte.lowercased(first)
            var index = start
            while index < bytes.count {
                let byte = bytes[index]
                let candidate = caseInsensitive ? Byte.lowercased(byte) == firstLower : byte == first
                if candidate, matches(pattern, at: index, caseInsensitive: caseInsensitive) { return index }
                index += 1
            }
            return nil
        }
    }

    /// Collapses runs of spaces, trims each line and drops empty lines.
    private static func tidy(_ text: [UInt8]) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(text.count)
        var lineHasContent = false
        var pendingSpace = false
        for byte in text {
            switch byte {
            case Byte.newline:
                lineHasContent = false
                pendingSpace = false
            case Byte.space:
                pendingSpace = lineHasContent
            default:
                if !lineHasContent {
                    if !result.isEmpty { result.append(Byte.newline) }
                    lineHasContent = true
                } else if pendingSpace {
                    result.append(Byte.space)
                }
                pendingSpace = false
                result.append(byte)
            }
        }
        return result
    }

    private enum Byte {
        static let lessThan = UInt8(ascii: "<")
        static let greaterThan = UInt8(ascii: ">")
        static let ampersand = UInt8(ascii: "&")
        static let semicolon = UInt8(ascii: ";")
        static let slash = UInt8(ascii: "/")
        static let bang = UInt8(ascii: "!")
        static let question = UInt8(ascii: "?")
        static let hash = UInt8(ascii: "#")
        static let space = UInt8(ascii: " ")
        static let newline = UInt8(ascii: "\n")
        static let tab = UInt8(ascii: "\t")

        /// Bytes the scanner handles itself: markup, references and line breaks.
        static func isSpecial(_ byte: UInt8) -> Bool {
            byte == lessThan || byte == ampersand || byte == newline || byte == tab || byte == UInt8(ascii: "\r")
        }

        static func isLetter(_ byte: UInt8) -> Bool {
            (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
        }

        static func isDigit(_ byte: UInt8) -> Bool {
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
        }

        /// ASCII-only lowercasing; other bytes are returned unchanged.
        static func lowercased(_ byte: UInt8) -> UInt8 {
            (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte | 0x20 : byte
        }
    }

    private static let skippedElements: Set<String> = [
        "script", "style", "head", "title", "template", "noscript",
    ]

    private static let lineBreakElements: Set<String> = [
        "br", "p", "div", "li", "tr", "ul", "ol", "table", "blockquote", "pre", "hr",
        "h1", "h2", "h3", "h4", "h5", "h6", "section", "article", "header", "footer", "dt", "dd",
    ]

    private static let namedReferences: [String: UInt32] = [
        "amp": 0x26, "lt": 0x3C, "gt": 0x3E, "quot": 0x22, "apos": 0x27, "nbsp": 0xA0,
        "copy": 0xA9, "reg": 0xAE, "trade": 0x2122, "hellip": 0x2026, "mdash": 0x2014,
        "ndash": 0x2013, "lsquo": 0x2018, "rsquo": 0x2019, "ldquo": 0x201C, "rdquo": 0x201D,
        "bull": 0x2022, "middot": 0xB7, "euro": 0x20AC, "laquo": 0xAB, "raquo": 0xBB,
        "deg": 0xB0, "times": 0xD7,
    ]
}
