import Foundation

/// Filters and ranks clips for the panel's search field.
///
/// Matching is case- and diacritic-insensitive and every whitespace-separated
/// token must match. Each token scores by its best match: at the start of a
/// word, anywhere, or (for tokens of three or more characters) as a
/// subsequence near the start of the clip. Higher totals rank first; ties go
/// to the most recently copied clip.
public enum ClipSearch {
    /// How far into a clip's search text a fuzzy (subsequence) match may reach.
    static let fuzzyWindow = 256
    static let minimumFuzzyTokenLength = 3

    /// Clips matching `query` and `filter`, best first. An empty query lists
    /// the pins (in pin order) and then the recent clips.
    public static func results(
        for query: String,
        filter: ClipFilter = .all,
        pinned: [Clip],
        recent: [Clip]
    ) -> [Clip] {
        let tokens = query
            .split(whereSeparator: { $0.isWhitespace })
            .map { SearchKey.fold(String($0)) }
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else {
            return pinned.filter(filter.includes) + recent.filter(filter.includes)
        }

        var matches: [(clip: Clip, score: Int, order: Int)] = []
        for (order, clip) in (pinned + recent).enumerated() where filter.includes(clip) {
            if let score = score(clip.searchKey.bytes, tokens: tokens) {
                matches.append((clip, score, order))
            }
        }
        matches.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.clip.lastCopiedAt != rhs.clip.lastCopiedAt {
                return lhs.clip.lastCopiedAt > rhs.clip.lastCopiedAt
            }
            return lhs.order < rhs.order
        }
        return matches.map(\.clip)
    }

    /// How well a token matched; the raw value is its score.
    enum MatchQuality: Int, Comparable {
        case subsequence = 1
        case substring = 2
        case wordStart = 3

        static func < (lhs: MatchQuality, rhs: MatchQuality) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// The summed token scores, or `nil` when some token doesn't match.
    static func score(_ text: [UInt8], tokens: [[UInt8]]) -> Int? {
        var total = 0
        for token in tokens {
            guard let quality = match(token, in: text) else { return nil }
            total += quality.rawValue
        }
        return total
    }

    static func match(_ token: [UInt8], in text: [UInt8]) -> MatchQuality? {
        text.withUnsafeBufferPointer { haystack in
            token.withUnsafeBufferPointer { needle in
                match(needle, in: haystack)
            }
        }
    }

    private static func match(_ needle: UnsafeBufferPointer<UInt8>, in haystack: UnsafeBufferPointer<UInt8>) -> MatchQuality? {
        guard let needleStart = needle.baseAddress, let haystackStart = haystack.baseAddress,
              needle.count <= haystack.count
        else { return nil }

        let first = Int32(needle[0])
        let lastStart = haystack.count - needle.count
        var position = 0
        var foundSubstring = false
        while position <= lastStart {
            guard let hit = memchr(haystackStart + position, first, lastStart - position + 1) else { break }
            let index = UnsafeRawPointer(hit) - UnsafeRawPointer(haystackStart)
            if needle.count == 1 || memcmp(haystackStart + index + 1, needleStart + 1, needle.count - 1) == 0 {
                if index == 0 || isWordBoundary(haystack[index - 1]) { return .wordStart }
                foundSubstring = true
            }
            position = index + 1
        }
        if foundSubstring { return .substring }

        guard needle.count >= minimumFuzzyTokenLength else { return nil }
        var next = 0
        for byte in haystack.prefix(fuzzyWindow) where byte == needle[next] {
            next += 1
            if next == needle.count { return .subsequence }
        }
        return nil
    }

    /// Whether a match after `byte` starts a word. Non-ASCII bytes count as
    /// letters, so a match inside "naïve" isn't a word start.
    private static func isWordBoundary(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"), 0x80...:
            false
        default:
            true
        }
    }
}
