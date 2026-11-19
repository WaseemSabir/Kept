import Foundation

/// Recognizes text that is a single CSS-style color.
enum ColorParser {
    /// Longer text is never a color; checked before any other work.
    static let maxLength = 128

    /// The color `text` spells, as uppercase `#RRGGBB` (or `#RRGGBBAA` when
    /// not opaque). Accepts `#RRGGBB`, `#RRGGBBAA`, `rgb(…)` and `rgba(…)`
    /// with commas or spaces and an alpha after `/`, and the short `#RGB`
    /// and `#RGBA` forms when they can't be something else (see
    /// `isLikelyShortColor(_:)`). Only ASCII digits count.
    static func hex(from text: String) -> String? {
        guard text.utf8.count <= maxLength else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("#") {
            return hexNotation(trimmed.utf8.dropFirst())
        }
        for function in ["rgba(", "rgb("] where trimmed.hasPrefix(function) && trimmed.hasSuffix(")") {
            return functionalNotation(trimmed.dropFirst(function.count).dropLast())
        }
        return nil
    }

    private static func hexNotation(_ digits: Substring.UTF8View) -> String? {
        guard digits.allSatisfy(isHexDigit) else { return nil }
        let expanded: [UInt8]
        switch digits.count {
        case 6, 8:
            expanded = Array(digits)
        case 3, 4:
            guard isLikelyShortColor(Array(digits)) else { return nil }
            expanded = digits.flatMap { [$0, $0] }
        default:
            return nil
        }
        var hex = String(decoding: expanded, as: UTF8.self).uppercased()
        if hex.count == 8, hex.hasSuffix("FF") {
            hex.removeLast(2)
        }
        return "#" + hex
    }

    /// `#RGB` and `#RGBA` collide with issue references (`#123`, `#1234`)
    /// and words (`#add`, `#cafe`, `#beef`), so they count only when they
    /// mix digits and letters (`#f60`, `#0af8`) or repeat one digit, as
    /// grays and black and white do (`#333`, `#fff`, `#0000`).
    private static func isLikelyShortColor(_ digits: [UInt8]) -> Bool {
        if Set(digits).count == 1 { return true }
        let hasDecimal = digits.contains { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
        let hasLetter = digits.contains { (UInt8(ascii: "a")...UInt8(ascii: "f")).contains($0) }
        return hasDecimal && hasLetter
    }

    private static func functionalNotation(_ arguments: Substring) -> String? {
        let parts = arguments
            .split(whereSeparator: { $0 == "," || $0 == "/" || $0.isWhitespace })
        guard parts.count == 3 || parts.count == 4 else { return nil }

        var channels: [Int] = []
        for part in parts.prefix(3) {
            guard let channel = channel(part) else { return nil }
            channels.append(channel)
        }
        if parts.count == 4 {
            guard let alpha = alpha(parts[3]) else { return nil }
            if alpha < 255 { channels.append(alpha) }
        }
        return "#" + channels.map { String(format: "%02X", $0) }.joined()
    }

    /// 0–255, or 0%–100%.
    private static func channel(_ text: Substring) -> Int? {
        if text.hasSuffix("%") {
            guard let percent = decimal(text.dropLast()), (0...100).contains(percent) else { return nil }
            return Int((percent * 255 / 100).rounded())
        }
        guard let value = decimal(text), (0...255).contains(value) else { return nil }
        return Int(value.rounded())
    }

    /// 0–1, or 0%–100%, scaled to 0–255.
    private static func alpha(_ text: Substring) -> Int? {
        if text.hasSuffix("%") {
            guard let percent = decimal(text.dropLast()), (0...100).contains(percent) else { return nil }
            return Int((percent * 255 / 100).rounded())
        }
        guard let value = decimal(text), (0...1).contains(value) else { return nil }
        return Int((value * 255).rounded())
    }

    /// A plain decimal such as `255`, `0.5` or `.5`: ASCII digits and at
    /// most one point. No signs, exponents, hex or other scripts' digits.
    private static func decimal(_ text: Substring) -> Double? {
        var digits = 0
        var points = 0
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digits += 1
            case UInt8(ascii: "."): points += 1
            default: return nil
            }
        }
        guard digits > 0, points <= 1, text.last != "." else { return nil }
        return Double(text)
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
    }
}
