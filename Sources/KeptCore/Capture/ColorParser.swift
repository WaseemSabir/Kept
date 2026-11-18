import Foundation

/// Recognizes text that is a single CSS-style color.
enum ColorParser {
    /// The color `text` spells, as uppercase `#RRGGBB` (or `#RRGGBBAA` when
    /// not opaque). Accepts `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`,
    /// `rgb(…)` and `rgba(…)` with commas or spaces, and an alpha after `/`.
    static func hex(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("#") {
            return hexNotation(trimmed.dropFirst())
        }
        for function in ["rgba(", "rgb("] where trimmed.hasPrefix(function) && trimmed.hasSuffix(")") {
            return functionalNotation(trimmed.dropFirst(function.count).dropLast())
        }
        return nil
    }

    private static func hexNotation(_ digits: Substring) -> String? {
        guard [3, 4, 6, 8].contains(digits.count), digits.allSatisfy(\.isHexDigit) else { return nil }
        var expanded = digits.count <= 4 ? digits.map { "\($0)\($0)" }.joined() : String(digits)
        if expanded.count == 8, expanded.hasSuffix("ff") {
            expanded.removeLast(2)
        }
        return "#" + expanded.uppercased()
    }

    private static func functionalNotation(_ arguments: Substring) -> String? {
        let parts = arguments
            .split(whereSeparator: { $0 == "," || $0 == "/" || $0.isWhitespace })
            .map(String.init)
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
    private static func channel(_ text: String) -> Int? {
        if text.hasSuffix("%") {
            guard let percent = Double(text.dropLast()), (0...100).contains(percent) else { return nil }
            return Int((percent * 255 / 100).rounded())
        }
        guard let value = Double(text), (0...255).contains(value) else { return nil }
        return Int(value.rounded())
    }

    /// 0–1, or 0%–100%, scaled to 0–255.
    private static func alpha(_ text: String) -> Int? {
        if text.hasSuffix("%") {
            guard let percent = Double(text.dropLast()), (0...100).contains(percent) else { return nil }
            return Int((percent * 255 / 100).rounded())
        }
        guard let value = Double(text), (0...1).contains(value) else { return nil }
        return Int((value * 255).rounded())
    }
}
