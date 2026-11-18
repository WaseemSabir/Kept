import Foundation

/// Pulls the visible text out of an HTML fragment without a web view.
///
/// Good enough for titles, search and dedup of clips that carry HTML but no
/// plain string; pasting always uses the original bytes. Tags are dropped,
/// block elements become line breaks, `script`/`style`/`head` content and
/// comments are skipped, and common character references are decoded.
enum HTMLTextExtractor {
    static func plainText(from data: Data) -> String {
        plainText(from: String(decoding: data, as: UTF8.self))
    }

    static func plainText(from html: String) -> String {
        let scalars = Array(html.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]
            switch scalar {
            case "<":
                index = skipMarkup(in: scalars, from: index, into: &output)
            case "&":
                index = decodeReference(in: scalars, from: index, into: &output)
            case "\n", "\r", "\t":
                output.append(" ")
                index += 1
            default:
                output.append(scalar)
                index += 1
            }
        }
        return tidy(String(output))
    }

    /// Consumes a tag, comment or skipped element starting at `start` (a
    /// `<`), and returns the index just past it.
    private static func skipMarkup(
        in scalars: [Unicode.Scalar],
        from start: Int,
        into output: inout String.UnicodeScalarView
    ) -> Int {
        if matches(scalars, at: start, "<!--") {
            return firstIndex(of: "-->", in: scalars, from: start + 4).map { $0 + 3 } ?? scalars.count
        }
        guard let end = scalars[start...].firstIndex(of: ">") else {
            // A lone "<" is text.
            output.append("<")
            return start + 1
        }
        let name = tagName(in: scalars[(start + 1)..<end])
        let isClosing = scalars.indices.contains(start + 1) && scalars[start + 1] == "/"

        if !isClosing, skippedElements.contains(name) {
            return firstIndex(of: "</\(name)", in: scalars, from: end + 1, caseInsensitive: true)
                .flatMap { closeStart in scalars[closeStart...].firstIndex(of: ">").map { $0 + 1 } }
                ?? scalars.count
        }
        if lineBreakElements.contains(name) {
            output.append("\n")
        } else if name == "td" || name == "th" {
            output.append("\t")
        }
        return end + 1
    }

    private static func tagName(in tag: ArraySlice<Unicode.Scalar>) -> String {
        var name = String.UnicodeScalarView()
        for scalar in tag.drop(while: { $0 == "/" }) {
            guard scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) else { break }
            name.append(scalar)
        }
        return String(name).lowercased()
    }

    /// Decodes `&name;`, `&#123;` or `&#x1F600;` at `start`, or copies the
    /// ampersand when it isn't a reference Kept knows.
    private static func decodeReference(
        in scalars: [Unicode.Scalar],
        from start: Int,
        into output: inout String.UnicodeScalarView
    ) -> Int {
        let limit = min(scalars.count, start + 12)
        guard let semicolon = scalars[start..<limit].firstIndex(of: ";") else {
            output.append("&")
            return start + 1
        }
        let body = String(String.UnicodeScalarView(scalars[(start + 1)..<semicolon]))
        var value: UInt32?
        if body.hasPrefix("#x") || body.hasPrefix("#X") {
            value = UInt32(body.dropFirst(2), radix: 16)
        } else if body.hasPrefix("#") {
            value = UInt32(body.dropFirst())
        } else {
            value = namedReferences[body]
        }
        guard let value, let scalar = Unicode.Scalar(value) else {
            output.append("&")
            return start + 1
        }
        output.append(scalar)
        return semicolon + 1
    }

    private static func matches(
        _ scalars: [Unicode.Scalar], at index: Int, _ pattern: String, caseInsensitive: Bool = false
    ) -> Bool {
        var position = index
        for expected in pattern.unicodeScalars {
            guard position < scalars.count else { return false }
            let actual = scalars[position]
            let equal = caseInsensitive
                ? actual.properties.lowercaseMapping == expected.properties.lowercaseMapping
                : actual == expected
            guard equal else { return false }
            position += 1
        }
        return true
    }

    /// Where `pattern` next starts at or after `start`.
    private static func firstIndex(
        of pattern: String, in scalars: [Unicode.Scalar], from start: Int, caseInsensitive: Bool = false
    ) -> Int? {
        var index = start
        while index < scalars.count {
            if matches(scalars, at: index, pattern, caseInsensitive: caseInsensitive) { return index }
            index += 1
        }
        return nil
    }

    /// Collapses spaces, trims each line and drops empty lines.
    private static func tidy(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
