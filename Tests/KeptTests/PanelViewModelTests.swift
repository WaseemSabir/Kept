import Foundation
import Testing
@testable import Kept
import KeptCore

@MainActor
@Suite("Panel view model")
struct PanelViewModelTests {
    let directory: URL

    init() throws {
        directory = try makeTemporaryDirectory()
    }

    private func makeModel(
        _ texts: [String],
        paster: RecordingPaster? = RecordingPaster(),
        options: PasteOptions = PasteOptions()
    ) throws -> (PanelViewModel, HistoryStore) {
        let store = try makeStore(in: directory, texts: texts)
        let model = PanelViewModel(store: store, paster: paster, pasteOptions: { options })
        return (model, store)
    }

    private func titles(_ model: PanelViewModel) -> [String] {
        model.results.map(\.title)
    }

    // MARK: Selection

    @Test("Opens with the first row selected")
    func opensOnFirstRow() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, _) = try makeModel(["one", "two", "three"])
        model.prepareForShow()
        #expect(titles(model) == ["one", "two", "three"])
        #expect(model.selectedIndex == 0)
        #expect(model.presentationCount == 1)
    }

    @Test("Moving the selection stops at both ends")
    func movementClamps() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, _) = try makeModel(["one", "two", "three"])
        model.perform(.moveSelection(by: -1))
        #expect(model.selectedIndex == 0)
        model.perform(.moveSelection(by: 1))
        model.perform(.moveSelection(by: 1))
        model.perform(.moveSelection(by: 1))
        #expect(model.selectedIndex == 2)
        model.perform(.selectFirst)
        #expect(model.selectedIndex == 0)
        model.perform(.selectLast)
        #expect(model.selectedIndex == 2)
    }

    @Test("Paging moves by the page size and clamps")
    func paging() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, _) = try makeModel((1...25).map { "clip \($0)" })
        model.pageSize = 10
        model.perform(.movePage(by: 1))
        #expect(model.selectedIndex == 10)
        model.perform(.movePage(by: 1))
        model.perform(.movePage(by: 1))
        #expect(model.selectedIndex == 24)
        model.perform(.movePage(by: -1))
        #expect(model.selectedIndex == 14)
    }

    @Test("Deleting selects the next clip, or the previous one at the end")
    func deleteMovesSelection() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, _) = try makeModel(["one", "two", "three"])
        model.select(index: 1)
        model.perform(.delete)
        #expect(titles(model) == ["one", "three"])
        #expect(model.selectedClip?.title == "three")

        model.perform(.delete)
        #expect(titles(model) == ["one"])
        #expect(model.selectedClip?.title == "one")

        model.perform(.delete)
        #expect(model.results.isEmpty)
        #expect(model.selectedID == nil)
        #expect(model.emptyState?.title == "Copy something and it shows up here.")
    }

    @Test("Pinning keeps the clip selected and moves it into the pinned section")
    func pinning() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store) = try makeModel(["one", "two", "three"])
        model.select(index: 2)
        model.perform(.togglePin)
        #expect(store.pinned.map(\.title) == ["three"])
        #expect(titles(model) == ["three", "one", "two"])
        #expect(model.selectedClip?.title == "three")
        #expect(model.sectionBreakIndex == 1)
        #expect(model.pinActionTitle == "Unpin")

        model.perform(.togglePin)
        #expect(store.pinned.isEmpty)
        #expect(model.sectionBreakIndex == nil)
    }

    // MARK: Query and filter

    @Test("Typing selects the best match; Esc clears, then closes")
    func queryAndEscape() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, _) = try makeModel(["apple pie", "banana bread", "cherry tart"])
        var dismissed = 0
        model.onDismiss = { dismissed += 1 }
        model.select(index: 2)
        model.query = "bread"
        #expect(titles(model) == ["banana bread"])
        #expect(model.selectedIndex == 0)

        model.perform(.cancel)
        #expect(model.query.isEmpty)
        #expect(dismissed == 0)
        model.perform(.cancel)
        #expect(dismissed == 1)
    }

    @Test("⌃U clears the query")
    func clearQuery() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, _) = try makeModel(["apple"])
        model.query = "zzz"
        #expect(model.results.isEmpty)
        #expect(model.emptyState?.title == "No clips match “zzz”.")
        model.perform(.clearQuery)
        #expect(model.query.isEmpty)
        #expect(titles(model) == ["apple"])
    }

    @Test("Tab and ⇧Tab cycle through the filters and wrap around")
    func filterCycling() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, _) = try makeModel(["one"])
        #expect(model.filter == .all)
        model.perform(.nextFilter)
        #expect(model.filter == .pinned)
        #expect(model.emptyState?.title == "No pinned clips yet.")
        model.perform(.previousFilter)
        model.perform(.previousFilter)
        #expect(model.filter == .files)
        model.perform(.nextFilter)
        #expect(model.filter == .all)
    }

    @Test("Opening again resets the query, filter and selection")
    func resetsOnShow() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, _) = try makeModel(["one", "two"])
        model.query = "two"
        model.filter = .text
        model.prepareForShow()
        #expect(model.query.isEmpty)
        #expect(model.filter == .all)
        #expect(model.selectedIndex == 0)
    }

    // MARK: Actions

    @Test("⏎, ⌥⏎, ⌘⏎, ⌘N, ⌥⌘N and a double-click each ask for their paste")
    func activation() throws {
        defer { removeTemporaryDirectory(directory) }
        let paster = RecordingPaster()
        let (model, _) = try makeModel(["one", "two", "three"], paster: paster)
        var dismissed = 0
        model.onDismiss = { dismissed += 1 }

        model.select(index: 1)
        model.perform(.activate(alternate: false))
        model.perform(.activate(alternate: true))
        model.perform(.copyOnly)
        model.perform(.activateRow(2, alternate: false))
        model.perform(.activateRow(0, alternate: true))
        // Row 9 doesn't exist: nothing happens.
        model.perform(.activateRow(8, alternate: false))
        model.activate(try #require(model.results.last))
        #expect(paster.pastes == [
            RecordingPaster.Paste(title: "two", request: .paste(alternate: false)),
            RecordingPaster.Paste(title: "two", request: .paste(alternate: true)),
            RecordingPaster.Paste(title: "two", request: .copyOnly),
            RecordingPaster.Paste(title: "three", request: .paste(alternate: false)),
            RecordingPaster.Paste(title: "one", request: .paste(alternate: true)),
            RecordingPaster.Paste(title: "three", request: .paste(alternate: false)),
        ])
        #expect(paster.completed.count == 6)
        #expect(dismissed == 6)
        #expect(model.selectedClip?.title == "three")
    }

    @Test("The panel closes after the clip is written and before ⌘V, and passes its frame along")
    func pasteOrder() throws {
        defer { removeTemporaryDirectory(directory) }
        let paster = RecordingPaster()
        let log = EventLog()
        paster.log = log
        let (model, _) = try makeModel(["one"], paster: paster)
        let frame = CGRect(x: 100, y: 200, width: 720, height: 460)
        model.hintAnchor = { frame }
        model.onDismiss = { log.events.append("dismiss") }

        model.perform(.activate(alternate: false))
        #expect(log.events == ["prepare", "dismiss", "complete"])
        #expect(paster.anchors == [frame])
    }

    @Test("A failed copy keeps the panel open and says so")
    func copyFailure() throws {
        defer { removeTemporaryDirectory(directory) }
        let paster = RecordingPaster()
        paster.failure = TestSetupError(description: "nope")
        let (model, _) = try makeModel(["one"], paster: paster)
        var dismissed = false
        model.onDismiss = { dismissed = true }
        model.perform(.activate(alternate: false))
        #expect(!dismissed)
        #expect(paster.completed.isEmpty)
        #expect(model.notice == "Couldn't copy that clip.")
        model.perform(.moveSelection(by: 1))
        #expect(model.notice == nil)
    }

    @Test("Without a paster the panel stays open and says why")
    func noPaster() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, _) = try makeModel(["one"], paster: nil)
        var dismissed = false
        model.onDismiss = { dismissed = true }
        model.perform(.activate(alternate: false))
        #expect(!dismissed)
        #expect(model.notice == "Kept can't paste while its history is unavailable.")
    }

    @Test("Footer labels follow paste directly and always paste plain text")
    func footerLabels() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore(in: directory, texts: ["one"])
        let table: [(options: PasteOptions, primary: String, alternate: String, copyOnly: String?)] = [
            (PasteOptions(pasteDirectly: true, alwaysPastePlainText: false), "Paste", "Paste as plain text", "Copy"),
            (PasteOptions(pasteDirectly: true, alwaysPastePlainText: true), "Paste as plain text", "Paste with formatting", "Copy"),
            (PasteOptions(pasteDirectly: false, alwaysPastePlainText: false), "Copy", "Copy as plain text", nil),
            (PasteOptions(pasteDirectly: false, alwaysPastePlainText: true), "Copy as plain text", "Copy with formatting", nil),
        ]
        for row in table {
            let options = row.options
            let model = PanelViewModel(store: store, paster: RecordingPaster(), pasteOptions: { options })
            #expect(model.primaryActionTitle == row.primary, "\(options)")
            #expect(model.alternateActionTitle == row.alternate, "\(options)")
            #expect(model.copyOnlyActionTitle == row.copyOnly, "\(options)")
        }
    }

    @Test("Clearing unpinned clips asks first, clears only on ⌥⌘⌫ again, and keeps pins")
    func clearUnpinned() throws {
        defer { removeTemporaryDirectory(directory) }
        let paster = RecordingPaster()
        let (model, store) = try makeModel(["one", "two", "three"], paster: paster)
        model.select(index: 2)
        model.perform(.togglePin)

        model.perform(.requestClearUnpinned)
        #expect(model.isConfirmingClear)
        #expect(model.unpinnedCount == 2)
        #expect(model.clearConfirmationMessage == "Clear 2 unpinned clips? Pinned clips stay.")

        // ⏎ is the paste key: pressed by habit it neither clears nor pastes.
        for key in [PanelCommand.activate(alternate: false), .activate(alternate: true), .copyOnly, .activateRow(0, alternate: false)] {
            #expect(model.perform(key))
            #expect(model.isConfirmingClear)
        }
        #expect(store.recent.count == 2)
        #expect(paster.pastes.isEmpty)

        // Esc backs out without deleting; so does any other key.
        model.perform(.cancel)
        #expect(!model.isConfirmingClear)
        #expect(store.recent.count == 2)
        model.perform(.requestClearUnpinned)
        model.perform(.moveSelection(by: 1))
        #expect(!model.isConfirmingClear)
        #expect(store.recent.count == 2)

        // ⌥⌘⌫ again clears.
        model.perform(.requestClearUnpinned)
        model.perform(.requestClearUnpinned)
        #expect(!model.isConfirmingClear)
        #expect(store.recent.isEmpty)
        #expect(titles(model) == ["three"])

        model.perform(.requestClearUnpinned)
        #expect(!model.isConfirmingClear)
        #expect(model.notice == "There are no unpinned clips to clear.")
    }

    @Test("The bar's Clear button clears and its Cancel button backs out")
    func clearBarButtons() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store) = try makeModel(["one", "two"])
        model.perform(.requestClearUnpinned)
        model.cancelClearUnpinned()
        #expect(!model.isConfirmingClear)
        #expect(store.recent.count == 2)
        model.perform(.requestClearUnpinned)
        model.confirmClearUnpinned()
        #expect(store.recent.isEmpty)
    }

    @Test("⌘⌫ deletes the clip only while the search is empty; with a query it edits the field")
    func deleteKeyNeedsEmptyQuery() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store) = try makeModel(["apple pie", "apple tart", "cherry"])
        model.query = "apple"
        #expect(!model.canDeleteWithKey)
        // Not handled: the key goes on to the search field.
        #expect(model.perform(.delete) == false)
        #expect(store.recent.count == 3)

        // The context menu's Delete still works while searching.
        let tart = try #require(model.results.first { $0.title == "apple tart" })
        model.perform(.delete, on: tart)
        #expect(store.recent.map(\.title) == ["apple pie", "cherry"])

        model.query = ""
        #expect(model.canDeleteWithKey)
        #expect(model.perform(.delete))
        #expect(store.recent.map(\.title) == ["cherry"])
    }

    @Test("Typing dismisses the clear confirmation")
    func typingDismissesConfirmation() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, _) = try makeModel(["one"])
        model.perform(.requestClearUnpinned)
        model.query = "o"
        #expect(!model.isConfirmingClear)
    }

    @Test("Text editing commands are left to the search field")
    func editingIsNotHandled() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, _) = try makeModel(["one"])
        #expect(model.perform(.edit(.paste)) == false)
        #expect(model.perform(.moveSelection(by: 1)) == true)
    }

    // MARK: Scrolling

    @Test("The scroll token moves with the selected row, not only the selected clip")
    func scrollToken() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store) = try makeModel(["one", "two", "three"])
        var token = model.scrollToken

        func moved() -> Bool {
            defer { token = model.scrollToken }
            return model.scrollToken != token
        }

        model.perform(.moveSelection(by: 1))
        #expect(moved())
        model.perform(.selectFirst)
        #expect(moved())
        // Already at the top: nothing moved, nothing to scroll.
        model.perform(.selectFirst)
        #expect(!moved())

        // Pinning "three" moves it to row 0 while it stays selected.
        model.perform(.selectLast)
        #expect(moved())
        model.perform(.togglePin)
        #expect(model.selectedClip?.title == "three")
        #expect(model.selectedIndex == 0)
        #expect(moved())

        // Unpinning moves it back to the top of the history: same row 0, no scroll.
        model.perform(.togglePin)
        #expect(model.selectedIndex == 0)
        #expect(!moved())

        // A new copy pushes the selected clip down a row.
        try store.record(try textDraft("zero"), at: Date().addingTimeInterval(3_600))
        model.refresh()
        #expect(model.selectedClip?.title == "three")
        #expect(model.selectedIndex == 1)
        #expect(moved())

        // Refreshing with nothing changed doesn't scroll.
        model.refresh()
        #expect(!moved())
    }

    @Test("Moving a pin with ⌥⌘↓ scrolls with it")
    func scrollTokenFollowsPinMoves() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store) = try makeModel(["one", "two", "three"])
        for clip in store.recent.reversed() { try store.pin(clip.id) }
        model.refresh(selecting: .first)
        let token = model.scrollToken
        model.perform(.movePin(by: 1))
        #expect(model.selectedIndex == 1)
        #expect(model.scrollToken != token)
    }

    // MARK: Hidden panel

    @Test("While hidden the panel drops its query and doesn't search; opening refreshes")
    func hiddenPanelWaits() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store) = try makeModel(["one", "two"])
        model.query = "two"
        model.perform(.requestClearUnpinned)
        model.panelDidHide()
        #expect(model.query.isEmpty)
        #expect(model.filter == .all)
        #expect(!model.isConfirmingClear)
        // The search for "two" stays as it was: nothing ran while hidden.
        #expect(titles(model) == ["two"])

        try store.record(try textDraft("zero"), at: .at(100))
        model.refresh()
        #expect(titles(model) == ["two"])

        model.prepareForShow()
        #expect(titles(model) == ["zero", "one", "two"])
        #expect(model.selectedIndex == 0)
    }

    // MARK: VoiceOver

    @Test("Moving the selection announces the clip and its place in the list")
    func announcesSelection() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, _) = try makeModel(["one", "two", "three"])
        var spoken: [String] = []
        model.announce = { spoken.append($0) }

        model.perform(.moveSelection(by: 1))
        #expect(spoken.count == 1)
        #expect(spoken.last?.hasPrefix("Text, two, ") == true)
        #expect(spoken.last?.hasSuffix(". 2 of 3.") == true)

        model.perform(.togglePin)
        #expect(spoken.last?.contains(", pinned. 1 of 3.") == true)

        // Typing isn't interrupted by announcements.
        model.query = "t"
        #expect(spoken.count == 2)

        model.perform(.requestClearUnpinned)
        #expect(spoken.last?.hasPrefix("Clear 2 unpinned clips?") == true)
    }

    // MARK: History changes

    @Test("A new copy while open keeps the selected clip selected")
    func newCopyKeepsSelection() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store) = try makeModel(["one", "two"])
        model.select(index: 1)
        try store.record(try textDraft("zero"), at: .at(100))
        model.refresh()
        #expect(titles(model) == ["zero", "one", "two"])
        #expect(model.selectedClip?.title == "two")
    }

    @Test("Without a store the panel explains and stays usable")
    func unavailableStore() {
        let model = PanelViewModel(store: nil, unavailableReason: "The disk is full.")
        #expect(model.results.isEmpty)
        #expect(model.emptyState?.title == "Kept couldn't open your history.")
        #expect(model.emptyState?.hint == "The disk is full. Quit and reopen Kept to try again.")
        #expect(model.emptyState?.spansPanel == true)
        model.perform(.moveSelection(by: 1))
        model.perform(.delete)
        model.perform(.togglePin)
        #expect(model.selectedID == nil)
    }

    // MARK: Preview

    @Test("The preview keeps line breaks and counts lines")
    func preview() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, _) = try makeModel(["first line\nsecond line"])
        let clip = try #require(model.selectedClip)
        let preview = model.preview(for: clip)
        #expect(preview.content == .text("first line\nsecond line", isCode: false))
        #expect(preview.lineCount == 2)
        let facts = model.facts(for: clip, preview: preview)
        #expect(facts.map(\.label) == ["Copied", "Size", "Lines"])
        #expect(facts.first { $0.label == "Size" }?.value == "22 characters")
    }

    @Test("Huge text is cut for the preview")
    func previewTruncates() {
        let text = String(repeating: "a", count: PreviewLoader.maxCharacters + 5)
        let preview = PreviewLoader.textPreview(text, isCode: false)
        #expect(preview.truncatedFrom == PreviewLoader.maxCharacters + 5)
        if case .text(let shown, _) = preview.content {
            #expect(shown.count == PreviewLoader.maxCharacters)
        } else {
            Issue.record("Expected text content")
        }
        #expect(PreviewLoader.textPreview("short", isCode: false).truncatedFrom == nil)
    }
}
