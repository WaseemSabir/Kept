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

    @Test("Matches a clip's custom title as well as its content")
    func matchesCustomTitles() {
        let named = Clip(
            kind: .text,
            title: "Thanks for reaching out",
            customTitle: "Support reply",
            searchText: "Thanks for reaching out",
            contentHash: "a",
            firstCopiedAt: .at(-2),
            lastCopiedAt: .at(-2),
            byteSize: 23
        )
        let recent = [clip("supportive words", age: 1), named]
        #expect(ClipSearch.results(for: "support", pinned: [], recent: recent).map(\.displayTitle) == ["supportive words", "Support reply"])
        #expect(ClipSearch.results(for: "reaching", pinned: [], recent: recent).map(\.id) == [named.id])
        #expect(ClipSearch.results(for: "reply thanks", pinned: [], recent: recent).map(\.id) == [named.id])
        // Each starts words: "thanks" is a word start, not a substring.
        #expect(ClipSearch.results(for: "thanks", pinned: [], recent: [named, clip("nothanks", age: 3)]).map(\.id).first == named.id)
        #expect(named.displayTitle == "Support reply")
        #expect(clip("plain").displayTitle == "plain")
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

    @Test("Matches a single CJK character only where it appears")
    func matchesSingleCJKCharacter() {
        // "京" is E4 BA AC in UTF-8; these clips hold those bytes, scattered.
        let recent = [clip("東京", age: 1), clip("人 交 䬬", age: 2), clip("亮 京都", age: 3), clip("日本", age: 4)]
        #expect(titles("京", recent: recent) == ["亮 京都", "東京"])
        #expect(titles("京都", recent: recent) == ["亮 京都"])
    }

    @Test("Matches fuzzily on whole scalars, by typed characters")
    func matchesFuzzilyOnScalars() {
        let recent = [clip("東の京へ都", age: 1), clip("Ünïcödé text", age: 2)]
        #expect(titles("東京都", recent: recent) == ["東の京へ都"])
        #expect(titles("東京", recent: recent).isEmpty)  // two characters: no fuzzy match
        #expect(titles("unc", recent: recent) == ["Ünïcödé text"])
        #expect(titles("ucdt", recent: recent) == ["Ünïcödé text"])
    }

    @Test("Folds text the same way as before, scalar by scalar and in sentences")
    func foldsLikeFoundation() {
        // The BMP, mathematical alphanumerics (compatibility forms) and emoji.
        let ranges = [0x80..<0x1_0000, 0x1_D400..<0x1_D800, 0x1_F000..<0x1_FB00]
        var mismatches: [String] = []
        for value in ranges.joined() {
            guard let scalar = Unicode.Scalar(UInt32(value)) else { continue }
            let text = String(Character(scalar))
            if SearchKey.fold(text) != Self.referenceFold(text) {
                mismatches.append("U+" + String(value, radix: 16, uppercase: true))
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.prefix(20))")
        let sentences = [
            "Café au lait, s'il vous plaît", "Ångström Straße ﬁnance Œuvre", "Привет, мир! ЁЖИК", "Ελληνικά ΣΊΣΥΦΟΣ",
            "東京都 ｶﾀｶﾅ ｈｅｌｌｏ が ぱ", "한국어 텍스트", "Tiếng Việt có dấu", "عربي مع تشكيل: كَتَبَ", "हिन्दी पाठ",
            "emoji 👨‍👩‍👧 🇯🇵 ①②③ ㎏ ½", "İstanbul ıı ǅ ǈ ß ẞ",
        ]
        for sentence in sentences {
            #expect(SearchKey.fold(sentence) == Self.referenceFold(sentence), "\(sentence)")
        }
    }

    @Test("Builds and searches 10,000 non-ASCII clips quickly")
    func handlesManyNonASCIIClips() {
        var generator = SeededGenerator(seed: 7)
        let words = Self.nonASCIIVocabulary
        let texts = (0..<10_000).map { _ in
            let count = Int.random(in: 5...60, using: &generator)
            return (0..<count).map { _ in words.randomElement(using: &generator) ?? "" }.joined(separator: " ")
        }
        let clock = ContinuousClock()
        var recent: [Clip] = []
        let initTime = clock.measure {
            recent = texts.enumerated().map { index, text in clip(text, age: Double(index)) }
        }
        _ = ClipSearch.results(for: "warm", pinned: [], recent: recent)
        var slowest = Duration.zero
        for query in ["привет", "CAFE", "東京", "strasse", "ελλ", "zzz"] {
            slowest = max(slowest, clock.measure { _ = ClipSearch.results(for: query, pinned: [], recent: recent) })
        }

        #if DEBUG
        let (initBudget, queryBudget) = (Duration.seconds(5), Duration.milliseconds(800))
        #else
        let (initBudget, queryBudget) = (Duration.milliseconds(500), Duration.milliseconds(60))
        #endif
        #expect(initTime < initBudget, "creating 10,000 clips took \(initTime)")
        #expect(slowest < queryBudget, "slowest query took \(slowest)")
        #expect(!ClipSearch.results(for: "мир", pinned: [], recent: recent).isEmpty)
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

    /// The folding Kept shipped first: decompose the whole string, then drop
    /// marks and lowercase. `SearchKey.fold` must match it.
    private static func referenceFold(_ text: String) -> [UInt8] {
        let folded: [UInt32: String] = [
            0x00DF: "ss", 0x00E6: "ae", 0x0153: "oe", 0x00F8: "o", 0x0111: "d", 0x00F0: "d",
            0x0142: "l", 0x0127: "h", 0x0131: "i", 0x00FE: "th",
        ]
        var bytes: [UInt8] = []
        for scalar in text.decomposedStringWithCompatibilityMapping.unicodeScalars {
            if scalar.isASCII {
                let value = UInt8(scalar.value)
                bytes.append((0x41...0x5A).contains(value) ? value | 0x20 : value)
                continue
            }
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .enclosingMark: continue
            default: break
            }
            for lowered in scalar.properties.lowercaseMapping.unicodeScalars {
                bytes.append(contentsOf: (folded[lowered.value] ?? String(lowered)).utf8)
            }
        }
        return bytes
    }

    private static let nonASCIIVocabulary = """
        café naïve résumé déjà vu Ångström Straße façade jalapeño crème brûlée Øresund Łódź \
        привет мир документ отчёт встреча завтра ПРОЕКТ сервер Ελληνικά καλημέρα ΑΘΗΝΑ \
        東京 京都 日本語 中文 搜索 剪贴板 한국어 텍스트 ひらがな カタカナ \
        Tiếng Việt عربي हिन्दी deploy staging invoice 2026 report
        """.split(whereSeparator: { $0.isWhitespace }).map(String.init)

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
