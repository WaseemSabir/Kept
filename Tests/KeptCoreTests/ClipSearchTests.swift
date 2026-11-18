import Foundation
import Testing
@testable import KeptCore

@Suite("Clip search")
struct ClipSearchTests {
    /// A clip copied `age` seconds before a fixed "now".
    private func clip(
        _ text: String,
        kind: ClipKind = .text,
        age: Double = 0,
        pinOrder: Int? = nil
    ) -> Clip {
        Clip(
            kind: kind,
            title: text,
            searchText: text,
            contentHash: SHA256.hexDigest(of: text),
            firstCopiedAt: .at(-age),
            lastCopiedAt: .at(-age),
            pinOrder: pinOrder,
            byteSize: text.utf8.count
        )
    }

    private func titles(_ query: String, filter: ClipFilter = .all, pinned: [Clip] = [], recent: [Clip]) -> [String] {
        ClipSearch.results(for: query, filter: filter, pinned: pinned, recent: recent).map(\.title)
    }

    @Test("Ranks word starts above substrings above fuzzy matches, whatever their age")
    func ranksByMatchQuality() {
        let recent = [
            clip("Ramen expo", age: 1),
            clip("Prepared slides", age: 2),
            clip("Report Q3", age: 3),
            clip("Nothing here", age: 4),
        ]
        #expect(titles("rep", recent: recent) == ["Report Q3", "Prepared slides", "Ramen expo"])
    }

    @Test("Requires every token to match")
    func matchesAllTokens() {
        let recent = [
            clip("deploy to staging tonight", age: 1),
            clip("deploy to production", age: 2),
            clip("staging server notes", age: 3),
        ]
        #expect(titles("deploy staging", recent: recent) == ["deploy to staging tonight"])
        #expect(titles("  staging\t", recent: recent) == ["deploy to staging tonight", "staging server notes"])
    }

    @Test("Breaks ties by recency")
    func breaksTiesByRecency() {
        let recent = [clip("budget older", age: 9), clip("budget newer", age: 1), clip("budget middle", age: 5)]
        #expect(titles("budget", recent: recent) == ["budget newer", "budget middle", "budget older"])
    }

    @Test("Ignores case and diacritics in both directions")
    func foldsCaseAndDiacritics() {
        let recent = [clip("Café au lait", age: 1), clip("cafe racer", age: 2), clip("Straße 5", age: 3), clip("Ångström", age: 4)]
        #expect(titles("CAFE", recent: recent) == ["Café au lait", "cafe racer"])
        #expect(titles("café", recent: recent) == ["Café au lait", "cafe racer"])
        #expect(titles("strasse", recent: recent) == ["Straße 5"])
        #expect(titles("angstrom", recent: recent) == ["Ångström"])
    }

    @Test("Matches non-Latin text")
    func matchesNonLatinText() {
        let recent = [clip("你好世界", age: 1), clip("Привет мир", age: 2)]
        #expect(titles("世界", recent: recent) == ["你好世界"])
        #expect(titles("ПРИВЕТ", recent: recent) == ["Привет мир"])
    }

    @Test("Counts punctuation as a word boundary")
    func treatsPunctuationAsBoundary() {
        let recent = [clip("telecom bill", age: 1), clip("github.com/kept", age: 2)]
        #expect(titles("com", recent: recent) == ["github.com/kept", "telecom bill"])
    }

    @Test("Matches fuzzily only for longer tokens, near the start")
    func limitsFuzzyMatching() {
        let late = String(repeating: "x", count: 300) + " r p t"
        let recent = [clip("Report", age: 1), clip(late, age: 2)]
        #expect(titles("rpt", recent: recent) == ["Report"])
        #expect(titles("rp", recent: recent).isEmpty)
    }

    @Test("Filters by kind")
    func filtersByKind() {
        let pinned = [clip("pinned note", pinOrder: 0)]
        let recent = [
            clip("plain", kind: .text, age: 1),
            clip("rich", kind: .richText, age: 2),
            clip("#FF6A00", kind: .color, age: 3),
            clip("https://kept.app", kind: .link, age: 4),
            clip("Image 10 × 10", kind: .image, age: 5),
            clip("report.pdf", kind: .file, age: 6),
        ]
        #expect(titles("", filter: .text, pinned: pinned, recent: recent) == ["pinned note", "plain", "rich", "#FF6A00"])
        #expect(titles("", filter: .links, pinned: pinned, recent: recent) == ["https://kept.app"])
        #expect(titles("", filter: .images, pinned: pinned, recent: recent) == ["Image 10 × 10"])
        #expect(titles("", filter: .files, pinned: pinned, recent: recent) == ["report.pdf"])
        #expect(titles("", filter: .pinned, pinned: pinned, recent: recent) == ["pinned note"])
        #expect(titles("note", filter: .links, pinned: pinned, recent: recent).isEmpty)
    }

    @Test("Lists pins first, then recent clips, for an empty query")
    func listsEverythingForEmptyQuery() {
        let pinned = [clip("second pin", age: 1, pinOrder: 0), clip("first pin", age: 50, pinOrder: 1)]
        let recent = [clip("newest", age: 2), clip("older", age: 3)]
        let expected = ["second pin", "first pin", "newest", "older"]
        #expect(titles("", pinned: pinned, recent: recent) == expected)
        #expect(titles("   ", pinned: pinned, recent: recent) == expected)
    }

    @Test("Searches pins and recent clips together")
    func searchesPinsToo() {
        let pinned = [clip("invoice template", age: 10, pinOrder: 0)]
        let recent = [clip("invoice 2026-11", age: 1)]
        #expect(titles("invoice", pinned: pinned, recent: recent) == ["invoice 2026-11", "invoice template"])
    }

    @Test("Searches 5,000 clips quickly")
    func searchesQuickly() {
        var generator = SeededGenerator(seed: 42)
        let recent = (0..<5000).map { index in
            clip(Self.randomText(using: &generator), age: Double(index))
        }
        let queries = ["deploy", "staging server", "kpt", "the", "zzzz", "invoice 2026", "conf"]

        // Warm up, then time a round of queries.
        _ = ClipSearch.results(for: "warm", pinned: [], recent: recent)
        let clock = ContinuousClock()
        var slowest = Duration.zero
        for query in queries {
            let elapsed = clock.measure { _ = ClipSearch.results(for: query, pinned: [], recent: recent) }
            slowest = max(slowest, elapsed)
        }

        #if DEBUG
        let budget = Duration.milliseconds(400)  // unoptimized builds are ~10x slower
        #else
        let budget = Duration.milliseconds(30)
        #endif
        #expect(slowest < budget, "slowest query took \(slowest)")
        #expect(!ClipSearch.results(for: "deploy", pinned: [], recent: recent).isEmpty)
    }

    // MARK: Fixtures

    private static let vocabulary = """
        the a to of and in is for on with deploy staging server production release build test fix bug \
        meeting notes thursday invoice 2026 budget report draft review config json swift func return let \
        var import class struct enum https github com kept app docs api token user password email address \
        phone call tomorrow lunch project roadmap design panel search clipboard history pin paste copy \
        image file folder documents downloads desktop screenshot color background font size weight error \
        warning log debug trace request response header body status code 200 404 500 timeout retry queue
        """.split(whereSeparator: { $0.isWhitespace }).map(String.init)

    /// Mostly short clips, some paragraphs, a few long documents.
    private static func randomText(using generator: inout SeededGenerator) -> String {
        let roll = Int.random(in: 0..<100, using: &generator)
        let words = roll < 70 ? Int.random(in: 3...20, using: &generator)
            : roll < 95 ? Int.random(in: 50...200, using: &generator)
            : Int.random(in: 800...1300, using: &generator)
        return (0..<words).map { _ in vocabulary.randomElement(using: &generator) ?? "" }.joined(separator: " ")
    }
}

/// A deterministic random number generator (SplitMix64) for repeatable fixtures.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
