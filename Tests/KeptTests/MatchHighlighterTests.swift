import Testing
@testable import Kept

@Suite("Search match emphasis")
struct MatchHighlighterTests {
    /// The matched text, in order.
    private func matches(_ query: String, in text: String) -> [String] {
        MatchHighlighter.ranges(of: MatchHighlighter.tokens(of: query), in: text).map { String(text[$0]) }
    }

    @Test("Ignores case, diacritics and width, like the search")
    func insensitive() {
        #expect(matches("cafe", in: "Café au lait at the CAFÉ") == ["Café", "CAFÉ"])
        #expect(matches("ÉCOLE", in: "école") == ["école"])
        #expect(matches("ＡＢ", in: "ab") == ["ab"])
    }

    @Test("Marks every word of the query, each wherever it appears")
    func multipleTokens() {
        #expect(matches("ferry san", in: "1 Ferry Building, San Francisco") == ["Ferry", "San"])
        #expect(matches("pa", in: "paste the pasteboard") == ["pa", "pa"])
        #expect(matches("  ferry   ", in: "Ferry") == ["Ferry"])
    }

    @Test("Overlapping and touching matches merge into one run")
    func overlapping() {
        #expect(matches("past paste", in: "pasteboard") == ["paste"])
        #expect(matches("paste board", in: "pasteboard") == ["pasteboard"])
        #expect(matches("ab bc", in: "abc") == ["abc"])
    }

    @Test("Nothing is marked without a match or a query")
    func noMatch() {
        #expect(matches("zebra", in: "pasteboard").isEmpty)
        #expect(matches("", in: "pasteboard").isEmpty)
        #expect(matches("   ", in: "pasteboard").isEmpty)
        #expect(matches("a", in: "").isEmpty)
        // A fuzzy match ranks in the search, but there's no run to mark.
        #expect(matches("pstbrd", in: "pasteboard").isEmpty)
    }

    @Test("Runs cover the whole text and say which parts matched")
    func runs() {
        let runs = MatchHighlighter.runs(of: "the pasteboard", tokens: ["PASTE"])
        #expect(runs.map { String($0.text) } == ["the ", "paste", "board"])
        #expect(runs.map(\.isMatch) == [false, true, false])
        let plain = MatchHighlighter.runs(of: "plain", tokens: [])
        #expect(plain.map { String($0.text) } == ["plain"])
        #expect(plain.map(\.isMatch) == [false])
    }

    @Test("A word that matches everywhere marks a bounded number of places")
    func bounded() {
        let text = String(repeating: "a b ", count: 200)
        let ranges = MatchHighlighter.ranges(of: ["a"], in: text)
        #expect(ranges.count == MatchHighlighter.maxMatchesPerToken)
    }

    @Test("A row starts just before a match it would otherwise truncate")
    func excerpts() {
        func excerpt(_ query: String, _ text: String) -> String {
            MatchHighlighter.excerpt(of: text, tokens: MatchHighlighter.tokens(of: query))
        }
        #expect(excerpt("pasteboard", "func write(_ items: [NSPasteboardItem]) -> Int {") == "…[NSPasteboardItem]) -> Int {")
        #expect(
            excerpt("notes", "Thanks for the quick turnaround on the onboarding flow. Two small notes before we ship")
                == "…small notes before we ship"
        )
        // Early matches and no matches leave the text alone.
        #expect(excerpt("ferry", "1 Ferry Building, San Francisco, CA 94111") == "1 Ferry Building, San Francisco, CA 94111")
        #expect(excerpt("zzz", "nothing here matches the query at all, really") == "nothing here matches the query at all, really")
        #expect(excerpt("", "nothing here matches the query at all, really") == "nothing here matches the query at all, really")
        // No word starts nearby: cut mid-word.
        #expect(excerpt("x", String(repeating: "a", count: 40) + "xaa") == "…aaaaaaaaxaa")
    }
}
