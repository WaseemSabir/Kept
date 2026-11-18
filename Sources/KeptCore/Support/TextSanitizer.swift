/// Cleans clip text for display and search.
///
/// Every run of whitespace (including line breaks) becomes one space, and
/// scalars that render as nothing or can stall text layout are dropped:
/// control and format characters (joiners and emoji tag characters
/// excepted), Unicode noncharacters, and long runs of combining marks
/// ("Zalgo" text). Some of these hang CoreText on macOS 26.
enum TextSanitizer {
    /// The most combining marks kept after one base character.
    static let maxCombiningMarks = 8

    /// Extra scalars collected past a limit, so the final cut can land on a
    /// character boundary instead of splitting an emoji or accented letter.
    private static let boundarySlack = 64

    /// A single-line summary of `text`, at most `maxCharacters` long.
    static func singleLine(_ text: String, maxCharacters: Int = 1000) -> String {
        // Emoji and accented letters take several scalars per character.
        let collapsed = collapse(text, maxScalars: maxCharacters * 4 + boundarySlack)
        return String(collapsed.prefix(maxCharacters))
    }

    /// `text` collapsed onto one line for searching, at most `maxUTF8Bytes`
    /// long. Cuts happen on a character boundary.
    static func searchable(_ text: String, maxUTF8Bytes: Int = 8 * 1024) -> String {
        // A scalar is at least one UTF-8 byte, so this collects enough.
        let collapsed = collapse(text, maxScalars: maxUTF8Bytes + boundarySlack)
        guard collapsed.utf8.count > maxUTF8Bytes else { return collapsed }
        var end = collapsed.startIndex
        var bytes = 0
        for index in collapsed.indices {
            let size = collapsed[index].utf8.count
            if bytes + size > maxUTF8Bytes { break }
            bytes += size
            end = collapsed.index(after: index)
        }
        return String(collapsed[..<end])
    }

    /// Whether `text` has anything other than whitespace and invisible
    /// characters in it.
    static func hasVisibleContent(_ text: String) -> Bool {
        text.unicodeScalars.contains { !$0.properties.isWhitespace && keeps($0) }
    }

    /// Collapses whitespace and drops unsafe scalars, keeping at most
    /// `maxScalars` of the result.
    private static func collapse(_ text: String, maxScalars: Int) -> String {
        var output = String.UnicodeScalarView()
        var count = 0
        var pendingSpace = false
        var combiningRun = 0

        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                pendingSpace = count > 0
                combiningRun = 0
                continue
            }
            guard keeps(scalar) else { continue }

            if isCombiningMark(scalar) {
                combiningRun += 1
                if combiningRun > maxCombiningMarks { continue }
            } else {
                combiningRun = 0
            }

            let needed = pendingSpace ? 2 : 1
            guard count + needed <= maxScalars else { break }
            if pendingSpace {
                output.append(" ")
                pendingSpace = false
            }
            output.append(scalar)
            count += needed
        }
        return String(output)
    }

    private static func keeps(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        switch scalar.properties.generalCategory {
        case .control, .surrogate:
            return false
        case .format:
            // Joiners shape emoji and Indic/Persian text; tags build flag emoji.
            return value == 0x200C || value == 0x200D || (0xE0020...0xE007F).contains(value)
        default:
            return !scalar.properties.isNoncharacterCodePoint
        }
    }

    private static func isCombiningMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .spacingMark: true
        default: false
        }
    }
}
