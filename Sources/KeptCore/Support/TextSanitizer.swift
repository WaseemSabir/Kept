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
///
/// `multiline(_:maxUTF16Count:)` applies the same rules but keeps spaces,
/// tabs and line breaks, for text laid out on several lines (the preview).
public enum TextSanitizer {
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

    // MARK: Multi-line text

    /// `text` made safe to lay out on several lines: the scalars
    /// `singleLine(_:maxCharacters:)` drops are dropped and every character
    /// is capped the same way, but spaces and tabs stay, and every line
    /// break (CRLF, CR, vertical tab, form feed, NEL, U+2028, U+2029) becomes
    /// one LF. The result is at most `maxUTF16Count` UTF-16 code units long,
    /// cut on a character boundary; `isTruncated` says whether anything was
    /// cut. Linear in the length of `text`, and stops reading it once the
    /// limit is reached.
    public static func multiline(_ text: String, maxUTF16Count: Int) -> (text: String, isTruncated: Bool) {
        let limit = max(0, maxUTF16Count)
        // Room past the limit so the final cut can land on a character boundary.
        let budget = limit + 2 * boundarySlack
        var output = String.UnicodeScalarView()
        var units = 0
        var isTruncated = false
        var caps = CharacterCaps()
        var afterCarriageReturn = false

        func trimJoiners(ifTruncated wasTruncated: Bool) {
            guard wasTruncated else { return }
            while let last = output.last, isJoiner(last) {
                output.removeLast()
                units -= UTF16.width(last)
            }
        }

        /// Appends `scalar`, or returns `false` once the budget is spent.
        func append(_ scalar: Unicode.Scalar) -> Bool {
            let width = UTF16.width(scalar)
            guard units + width <= budget else {
                isTruncated = true
                return false
            }
            output.append(scalar)
            units += width
            return true
        }

        for scalar in text.unicodeScalars {
            if scalar == "\n", afterCarriageReturn {
                afterCarriageReturn = false
                continue
            }
            if isLineBreak(scalar) {
                // Nothing joins across a line break.
                trimJoiners(ifTruncated: caps.boundary(startingScalars: 0))
                afterCarriageReturn = scalar == "\r"
                guard append("\n") else { break }
                continue
            }
            if scalar.properties.isWhitespace {
                // Marks after a space form a character with it; a tab is a control.
                trimJoiners(ifTruncated: caps.boundary(startingScalars: scalar == "\t" ? 0 : 1))
                afterCarriageReturn = false
                guard append(scalar) else { break }
                continue
            }
            // A CR and an LF with anything between them are two line
            // breaks, as `lineCount(of:)` counts them, even if that
            // something is dropped.
            afterCarriageReturn = false
            guard keeps(scalar) else { continue }
            switch caps.step(scalar) {
            case .dropped:
                continue
            case .startsCharacter(let previousWasTruncated):
                trimJoiners(ifTruncated: previousWasTruncated)
            case .extendsCharacter:
                break
            }
            guard append(scalar) else { break }
        }
        trimJoiners(ifTruncated: caps.boundary(startingScalars: 0))

        var result = trimmingTrailingJoiners(capCharacters(String(output)))
        guard result.utf16.count > limit else { return (result, isTruncated) }

        var end = result.startIndex
        var used = 0
        for index in result.indices {
            let width = result[index].utf16.count
            if used + width > limit { break }
            used += width
            end = result.index(after: index)
        }
        if end == result.startIndex {
            // The first character alone is over the limit: cut between scalars.
            var scalars = String.UnicodeScalarView()
            used = 0
            for scalar in result.unicodeScalars {
                let width = UTF16.width(scalar)
                if used + width > limit { break }
                used += width
                scalars.append(scalar)
            }
            result = String(scalars)
        } else {
            result = String(result[..<end])
        }
        return (trimmingTrailingJoiners(result), true)
    }

    /// How many lines `text` has: one more than its line breaks (LF, CR or
    /// CRLF, vertical tab, form feed, NEL, U+2028, U+2029: what
    /// `Character.isNewline` counts). Counted on UTF-8 bytes, so a long text
    /// takes milliseconds, not a walk over its characters.
    public static func lineCount(of text: String) -> Int {
        var text = text
        return text.withUTF8 { bytes in
            var count = 1
            var index = 0
            let end = bytes.count
            while index < end {
                switch bytes[index] {
                case 0x0A, 0x0B, 0x0C:
                    count += 1
                case 0x0D:
                    count += 1
                    if index + 1 < end, bytes[index + 1] == 0x0A { index += 1 }
                case 0xC2:
                    // U+0085 NEL.
                    if index + 1 < end, bytes[index + 1] == 0x85 {
                        count += 1
                        index += 1
                    }
                case 0xE2:
                    // U+2028 LINE SEPARATOR and U+2029 PARAGRAPH SEPARATOR.
                    if index + 2 < end, bytes[index + 1] == 0x80, bytes[index + 2] == 0xA8 || bytes[index + 2] == 0xA9 {
                        count += 1
                        index += 2
                    }
                default:
                    break
                }
                index += 1
            }
            return count
        }
    }

    // MARK: Collapsing

    /// Collapses whitespace, drops unsafe scalars and caps each character's
    /// extending scalars, keeping at most `maxScalars` of the result.
    private static func collapse(_ text: String, maxScalars: Int) -> String {
        var output = String.UnicodeScalarView()
        var count = 0
        var pendingSpace = false
        var caps = CharacterCaps()

        /// A character whose tail was cut mustn't end in a joiner, which
        /// would glue the next character onto it.
        func trimJoiners(ifTruncated wasTruncated: Bool) {
            guard wasTruncated else { return }
            while let last = output.last, isJoiner(last) {
                output.removeLast()
                count -= 1
            }
        }

        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                // Marks after a space form a character with it.
                trimJoiners(ifTruncated: caps.boundary(startingScalars: 1))
                pendingSpace = count > 0
                continue
            }
            guard keeps(scalar) else { continue }
            switch caps.step(scalar) {
            case .dropped:
                continue
            case .startsCharacter(let previousWasTruncated):
                trimJoiners(ifTruncated: previousWasTruncated)
            case .extendsCharacter:
                break
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
        trimJoiners(ifTruncated: caps.boundary(startingScalars: 0))
        return String(output)
    }

    /// Follows the character being built from a stream of kept scalars and
    /// applies the per-character caps to it.
    private struct CharacterCaps {
        enum Step {
            /// The scalar begins a new character; the one before it lost
            /// scalars to a cap when `previousWasTruncated`.
            case startsCharacter(previousWasTruncated: Bool)
            case extendsCharacter
            /// Over a cap: leave the scalar out.
            case dropped
        }

        /// The last scalar seen, kept or dropped for a cap (scalars dropped
        /// as unsafe never join anything, so they aren't passed in).
        private var previous: Unicode.Scalar?
        private var scalars = 0
        private var marks = 0
        private var isTruncated = false

        mutating func step(_ scalar: Unicode.Scalar) -> Step {
            let isMark = TextSanitizer.isCombiningMark(scalar)
            let continues = previous.map { TextSanitizer.continuesCharacter(scalar, after: $0) }
                ?? TextSanitizer.isExtending(scalar)
            previous = scalar
            if continues {
                scalars += 1
                if isMark { marks += 1 }
                if scalars > TextSanitizer.maxScalarsPerCharacter
                    || (isMark && marks > TextSanitizer.maxCombiningMarks) {
                    isTruncated = true
                    return .dropped
                }
                return .extendsCharacter
            }
            let wasTruncated = isTruncated
            scalars = 1
            marks = 0
            isTruncated = false
            return .startsCharacter(previousWasTruncated: wasTruncated)
        }

        /// Ends the current character at whitespace, a line break or the end
        /// of the text, returning whether it was truncated. The next
        /// character starts with `startingScalars` already counted (1 after a
        /// space, which marks attach to).
        mutating func boundary(startingScalars: Int) -> Bool {
            let wasTruncated = isTruncated
            previous = nil
            scalars = startingScalars
            marks = 0
            isTruncated = false
            return wasTruncated
        }
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

    /// Scalars that end a line: LF, VT, FF, CR, NEL, LINE SEPARATOR and
    /// PARAGRAPH SEPARATOR.
    private static func isLineBreak(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0A...0x0D, 0x85, 0x2028, 0x2029: true
        default: false
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
