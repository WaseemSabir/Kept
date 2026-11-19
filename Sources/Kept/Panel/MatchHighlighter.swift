import Foundation

/// Where the query's words appear in a row's text, so the row can set them
/// in a heavier weight. For display only: matching and ranking stay in
/// `ClipSearch`. Like the search, it ignores case, diacritics and width, so
/// "cafe" marks "Café".
enum MatchHighlighter {
    /// At most this many places are marked per word, so a long title full
    /// of one letter stays cheap to draw.
    static let maxMatchesPerToken = 32
    /// About how many characters of a title a row shows before it
    /// truncates: a first match further in would be cut off.
    static let visiblePrefix = 20
    /// How much of what comes before the first match an excerpt keeps.
    static let leadingContext = 8

    /// The query's words, split on whitespace.
    static func tokens(of query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Every place a token appears in `text`, in order, with overlapping or
    /// touching places merged into one.
    static func ranges(of tokens: [String], in text: String) -> [Range<String.Index>] {
        guard !text.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        var found: [Range<String.Index>] = []
        for token in tokens where !token.isEmpty {
            var start = text.startIndex
            var count = 0
            while start < text.endIndex, count < maxMatchesPerToken,
                  let range = text.range(of: token, options: options, range: start..<text.endIndex),
                  !range.isEmpty {
                found.append(range)
                start = range.upperBound
                count += 1
            }
        }
        return merged(found)
    }

    /// `ranges` sorted, with overlapping or touching ones joined.
    static func merged(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    /// `text` from just before its first match, after "…", when that match
    /// would otherwise fall where the row truncates; otherwise `text`. The
    /// excerpt starts at a word when one begins shortly before the match.
    static func excerpt(of text: String, tokens: [String]) -> String {
        guard let first = ranges(of: tokens, in: text).first,
              text.distance(from: text.startIndex, to: first.lowerBound) > visiblePrefix
        else { return text }
        var start = text.index(first.lowerBound, offsetBy: -leadingContext)
        if let space = text[start..<first.lowerBound].firstIndex(where: \.isWhitespace) {
            start = text.index(after: space)
        }
        return "…" + text[start...]
    }

    /// `text` cut into runs, each saying whether it matched, for drawing.
    static func runs(of text: String, tokens: [String]) -> [(text: Substring, isMatch: Bool)] {
        let ranges = ranges(of: tokens, in: text)
        guard !ranges.isEmpty else { return [(text[...], false)] }
        var runs: [(text: Substring, isMatch: Bool)] = []
        var cursor = text.startIndex
        for range in ranges {
            if cursor < range.lowerBound { runs.append((text[cursor..<range.lowerBound], false)) }
            runs.append((text[range], true))
            cursor = range.upperBound
        }
        if cursor < text.endIndex { runs.append((text[cursor...], false)) }
        return runs
    }
}
