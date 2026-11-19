/// Cleans clip text for display and search.
///
/// Every run of whitespace (including line breaks) becomes one space, and
/// scalars that render as nothing or can stall text layout are dropped:
/// control and format characters (joiners and emoji tag characters
/// excepted), Unicode noncharacters, and oversized characters ("Zalgo"
/// text, or thousands of joiners, tags or skin-tone modifiers glued into one
/// character). Some of these hang CoreText on macOS 26.
///
/// Two limits apply to every character: at most `maxCombiningMarks`
/// combining marks, and at most `maxScalarsPerCharacter` scalars in all.
/// The first pass counts every scalar that extends a character (marks,
/// joiners and what they join, variation selectors, tags, skin tones,
/// conjoining jamo) without resetting on a joiner; a final pass over the
/// result's characters enforces the limit exactly.
enum TextSanitizer {
    /// The most combining marks kept in one character.
    static let maxCombiningMarks = 8

    /// The most scalars kept in one character. The longest emoji sequences
    /// (a family with skin tones) take 11.
    static let maxScalarsPerCharacter = 16

    /// Extra scalars collected past a limit, so the final cut can land on a
    /// character boundary instead of splitting an emoji or accented letter.
    private static let boundarySlack = 64

    /// A single-line summary of `text`, at most `maxCharacters` long.
    static func singleLine(_ text: String, maxCharacters: Int = 1000) -> String {
        // Emoji and accented letters take several scalars per character.
        let collapsed = capCharacters(collapse(text, maxScalars: maxCharacters * 4 + boundarySlack))
        return trimmingTrailingJoiners(String(collapsed.prefix(maxCharacters)))
    }

    /// `text` collapsed onto one line for searching, at most `maxUTF8Bytes`
    /// long. Cuts happen on a character boundary (on a scalar boundary only
    /// if the first character alone is over the budget), so the result is
    /// empty only when `text` has nothing visible.
    static func searchable(_ text: String, maxUTF8Bytes: Int = 8 * 1024) -> String {
        // A scalar is at least one UTF-8 byte, so this collects enough.
        let collapsed = capCharacters(collapse(text, maxScalars: maxUTF8Bytes + boundarySlack))
        guard collapsed.utf8.count > maxUTF8Bytes else { return trimmingTrailingJoiners(collapsed) }

        var end = collapsed.startIndex
        var bytes = 0
        for index in collapsed.indices {
            let size = collapsed[index].utf8.count
            if bytes + size > maxUTF8Bytes { break }
            bytes += size
            end = collapsed.index(after: index)
        }
        if end == collapsed.startIndex {
            var scalars = String.UnicodeScalarView()
            bytes = 0
            for scalar in collapsed.unicodeScalars {
                let size = UTF8.width(scalar)
                if bytes + size > maxUTF8Bytes { break }
                bytes += size
                scalars.append(scalar)
            }
            return trimmingTrailingJoiners(String(scalars))
        }
        return trimmingTrailingJoiners(String(collapsed[..<end]))
    }

    /// Whether `text` has anything other than whitespace and invisible
    /// characters in it.
    static func hasVisibleContent(_ text: String) -> Bool {
        text.unicodeScalars.contains { !$0.properties.isWhitespace && keeps($0) }
    }

    // MARK: Collapsing

    /// Collapses whitespace, drops unsafe scalars and caps each character's
    /// extending scalars, keeping at most `maxScalars` of the result.
    private static func collapse(_ text: String, maxScalars: Int) -> String {
        var output = String.UnicodeScalarView()
        var count = 0
        var pendingSpace = false
        /// The last scalar of the input that was kept or dropped for a cap
        /// (whatever was dropped as unsafe never joins anything).
        var previous: Unicode.Scalar?
        var clusterScalars = 0
        var clusterMarks = 0
        var clusterTruncated = false

        /// Ends the current character. If its tail was cut, a joiner left at
        /// the end would glue the next character onto it, so it goes.
        func finishCluster() {
            if clusterTruncated {
                while let last = output.last, isJoiner(last) {
                    output.removeLast()
                    count -= 1
                }
            }
            clusterScalars = 0
            clusterMarks = 0
            clusterTruncated = false
        }

        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                finishCluster()
                pendingSpace = count > 0
                // Marks after a space form a character with it.
                clusterScalars = 1
                previous = nil
                continue
            }
            guard keeps(scalar) else { continue }

            let isMark = isCombiningMark(scalar)
            let continues = previous.map { continuesCharacter(scalar, after: $0) } ?? isExtending(scalar)
            previous = scalar
            if continues {
                clusterScalars += 1
                if isMark { clusterMarks += 1 }
                if clusterScalars > maxScalarsPerCharacter || (isMark && clusterMarks > maxCombiningMarks) {
                    clusterTruncated = true
                    continue
                }
            } else {
                finishCluster()
                clusterScalars = 1
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
        finishCluster()
        return String(output)
    }

    /// Enforces `maxScalarsPerCharacter` on the final characters, which the
    /// first pass only approximates (e.g. Indic conjuncts, prepended marks).
    /// Each pass removes scalars, so it ends; one pass is the norm.
    private static func capCharacters(_ text: String) -> String {
        var text = text
        while text.contains(where: { $0.unicodeScalars.count > maxScalarsPerCharacter }) {
            var output = String.UnicodeScalarView()
            for character in text {
                let scalars = character.unicodeScalars
                guard scalars.count > maxScalarsPerCharacter else {
                    output.append(contentsOf: scalars)
                    continue
                }
                var kept = Array(scalars.prefix(maxScalarsPerCharacter))
                while let last = kept.last, isJoiner(last) { kept.removeLast() }
                output.append(contentsOf: kept)
            }
            text = String(output)
        }
        return text
    }

    private static func trimmingTrailingJoiners(_ text: String) -> String {
        var scalars = text.unicodeScalars
        guard let last = scalars.last, isJoiner(last) else { return text }
        while let last = scalars.last, isJoiner(last) { scalars.removeLast() }
        return String(scalars)
    }

    // MARK: Scalar classes

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

    private static func isJoiner(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x200D || scalar.value == 0x200C
    }

    /// Scalars that always extend the character before them: marks,
    /// variation selectors, ZWNJ (all Grapheme_Extend), ZWJ, emoji tags and
    /// skin-tone modifiers, and conjoining Hangul vowels and finals.
    private static func isExtending(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if scalar.properties.isGraphemeExtend || isCombiningMark(scalar) { return true }
        switch value {
        case 0x200D, 0x200C, 0xE0020...0xE007F, 0x1F3FB...0x1F3FF: return true
        case 0x1160...0x11FF, 0xD7B0...0xD7FF: return true  // Hangul jamo V and T
        default: return false
        }
    }

    /// Whether `scalar` continues the character that `previous` belongs to.
    /// Errs towards "yes", which only makes the caps count more.
    private static func continuesCharacter(_ scalar: Unicode.Scalar, after previous: Unicode.Scalar) -> Bool {
        if isExtending(scalar) { return true }
        let value = scalar.value
        switch previous.value {
        case 0x200D:
            // ZWJ sequences: an emoji after a joiner joins the emoji before it.
            return value > 0x7F && scalar.properties.isEmoji
        case 0x094D, 0x09CD, 0x0ACD, 0x0B4D, 0x0C4D, 0x0D4D:
            // Indic conjuncts: a consonant after a virama (Unicode 15.1, GB9c).
            return scalar.properties.generalCategory == .otherLetter
        case 0x1100...0x115F, 0xA960...0xA97F:
            // Hangul leading consonants run together.
            return (0x1100...0x115F).contains(value) || (0xA960...0xA97F).contains(value)
        case 0x0D4E, 0x111C2, 0x111C3, 0x1193F, 0x11941, 0x11A3A, 0x11A84...0x11A89, 0x11D46, 0x11F02:
            // Prepended letters attach to what follows.
            return true
        default:
            return false
        }
    }
}
