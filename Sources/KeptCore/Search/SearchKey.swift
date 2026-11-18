import Foundation

/// Text folded for matching: lowercased, with diacritics and compatibility
/// forms removed ("Café" → "cafe", "ﬁ" → "fi", "Straße" → "strasse"), as
/// UTF-8 bytes so matching can scan memory directly.
struct SearchKey: Sendable, Hashable {
    let bytes: [UInt8]

    init(_ text: String) {
        bytes = SearchKey.fold(text)
    }

    static func fold(_ text: String) -> [UInt8] {
        var bytes = Array(text.utf8)
        if bytes.allSatisfy({ $0 < 0x80 }) {
            for index in bytes.indices where (0x41...0x5A).contains(bytes[index]) {
                bytes[index] |= 0x20
            }
            return bytes
        }

        var folded: [UInt8] = []
        folded.reserveCapacity(bytes.count)
        for scalar in text.decomposedStringWithCompatibilityMapping.unicodeScalars {
            if scalar.isASCII {
                let value = UInt8(scalar.value)
                folded.append((0x41...0x5A).contains(value) ? value | 0x20 : value)
                continue
            }
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .enclosingMark: continue
            default: break
            }
            for lowered in scalar.properties.lowercaseMapping.unicodeScalars {
                if let replacement = foldedLetters[lowered.value] {
                    folded.append(contentsOf: replacement.utf8)
                } else {
                    folded.append(contentsOf: String(lowered).utf8)
                }
            }
        }
        return folded
    }

    /// Letters with no decomposition that people type without the mark.
    private static let foldedLetters: [UInt32: String] = [
        0x00DF: "ss", 0x00E6: "ae", 0x0153: "oe", 0x00F8: "o", 0x0111: "d", 0x00F0: "d",
        0x0142: "l", 0x0127: "h", 0x0131: "i", 0x00FE: "th",
    ]
}
