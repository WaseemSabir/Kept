import Foundation

/// Pulls the visible text out of RTF without AppKit.
///
/// Good enough for titles, search and dedup of clips that carry RTF but no
/// plain string; pasting always uses the original RTF bytes. Handles groups,
/// ignorable destinations (font and color tables, pictures, field
/// instructions…), `\'hh` escapes (Windows-1252), `\uN` escapes with `\ucN`
/// fallbacks and surrogate pairs, and the common special-character words.
enum RTFTextExtractor {
    static func plainText(from data: Data) -> String {
        var parser = Parser(bytes: [UInt8](data))
        parser.run()
        return parser.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct GroupState {
        var skipsText = false
        var unicodeFallbackLength = 1
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0
        var state = GroupState()
        var stack: [GroupState] = []
        var output = String.UnicodeScalarView()
        /// Fallback characters still to drop after a `\uN` escape.
        var pendingFallback = 0
        var highSurrogate: UInt32?

        var text: String { String(output) }

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        mutating func run() {
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                switch byte {
                case UInt8(ascii: "{"):
                    stack.append(state)
                    pendingFallback = 0
                    if peek(UInt8(ascii: "\\")), peek(UInt8(ascii: "*"), offset: 1) {
                        state.skipsText = true
                    }
                case UInt8(ascii: "}"):
                    state = stack.popLast() ?? GroupState()
                    pendingFallback = 0
                case UInt8(ascii: "\\"):
                    readControl()
                case 0x0A, 0x0D:
                    continue  // Raw line breaks are formatting, not text.
                default:
                    emitByte(byte)
                }
            }
        }

        private func peek(_ byte: UInt8, offset: Int = 0) -> Bool {
            index + offset < bytes.count && bytes[index + offset] == byte
        }

        private mutating func readControl() {
            guard index < bytes.count else { return }
            let first = bytes[index]

            guard isLetter(first) else {
                index += 1
                switch first {
                case UInt8(ascii: "'"):
                    guard index + 1 < bytes.count,
                          let high = hexValue(bytes[index]), let low = hexValue(bytes[index + 1])
                    else { return }
                    index += 2
                    emitByte(high << 4 | low)
                case UInt8(ascii: "\\"), UInt8(ascii: "{"), UInt8(ascii: "}"):
                    emitByte(first)
                case UInt8(ascii: "~"):
                    emit(0x00A0)
                case UInt8(ascii: "_"):
                    emit(0x2011)
                case UInt8(ascii: "*"):
                    state.skipsText = true
                case 0x0A, 0x0D:
                    emit(0x0A)
                default:
                    break  // `\-` (optional hyphen) and unknown symbols.
                }
                return
            }

            let wordStart = index
            while index < bytes.count, isLetter(bytes[index]) { index += 1 }
            let word = String(decoding: bytes[wordStart..<index], as: UTF8.self)

            var parameter: Int?
            let parameterStart = index
            if peek(UInt8(ascii: "-")) { index += 1 }
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
            if index > parameterStart {
                parameter = Int(String(decoding: bytes[parameterStart..<index], as: UTF8.self))
            }
            if peek(UInt8(ascii: " ")) { index += 1 }

            handle(word: word, parameter: parameter)
        }

        private mutating func handle(word: String, parameter: Int?) {
            if RTFTextExtractor.skippedDestinations.contains(word) {
                state.skipsText = true
                return
            }
            switch word {
            case "par", "line", "sect", "page", "row":
                emit(0x0A)
            case "tab", "cell":
                emit(0x09)
            case "uc":
                state.unicodeFallbackLength = max(0, parameter ?? 1)
            case "u":
                guard let parameter else { return }
                let value = UInt32(truncatingIfNeeded: parameter < 0 ? parameter + 65_536 : parameter)
                emitUnicode(value)
                pendingFallback = state.unicodeFallbackLength
            default:
                if let scalar = RTFTextExtractor.specialCharacters[word] {
                    emit(scalar)
                }
            }
        }

        private mutating func emitUnicode(_ value: UInt32) {
            switch value {
            case 0xD800...0xDBFF:
                highSurrogate = value
            case 0xDC00...0xDFFF:
                if let high = highSurrogate {
                    emit(0x10000 + ((high - 0xD800) << 10) + (value - 0xDC00))
                }
                highSurrogate = nil
            default:
                highSurrogate = nil
                emit(value)
            }
        }

        /// A literal byte from the document: plain ASCII or Windows-1252.
        private mutating func emitByte(_ byte: UInt8) {
            if pendingFallback > 0 {
                pendingFallback -= 1
                return
            }
            emit(RTFTextExtractor.windows1252(byte))
        }

        private mutating func emit(_ value: UInt32) {
            guard !state.skipsText, let scalar = Unicode.Scalar(value) else { return }
            output.append(scalar)
        }

        private func isLetter(_ byte: UInt8) -> Bool {
            (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
                || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
        }

        private func isDigit(_ byte: UInt8) -> Bool {
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
        }

        private func hexValue(_ byte: UInt8) -> UInt8? {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
            default: nil
            }
        }
    }

    /// Destinations whose content is never visible text.
    static let skippedDestinations: Set<String> = [
        "fonttbl", "colortbl", "stylesheet", "info", "pict", "object", "fldinst",
        "header", "headerl", "headerr", "headerf", "footer", "footerl", "footerr", "footerf",
        "themedata", "colorschememapping", "latentstyles", "datastore", "xmlnstbl",
        "listtable", "listoverridetable", "rsidtbl", "generator", "expandedcolortbl",
        "filetbl", "revtbl", "pgdsctbl", "bkmkstart", "bkmkend", "nonshppict", "shppict",
    ]

    static let specialCharacters: [String: UInt32] = [
        "emdash": 0x2014, "endash": 0x2013, "bullet": 0x2022,
        "lquote": 0x2018, "rquote": 0x2019, "ldblquote": 0x201C, "rdblquote": 0x201D,
        "emspace": 0x2003, "enspace": 0x2002, "qmspace": 0x2005,
    ]

    /// Maps a Windows-1252 byte to its Unicode scalar value.
    static func windows1252(_ byte: UInt8) -> UInt32 {
        guard (0x80...0x9F).contains(byte) else { return UInt32(byte) }
        let table: [UInt32] = [
            0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
            0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
            0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
            0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
        ]
        return table[Int(byte - 0x80)]
    }
}
