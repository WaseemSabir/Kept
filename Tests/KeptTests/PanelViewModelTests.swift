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
        copier: RecordingCopier? = RecordingCopier()
    ) throws -> (PanelViewModel, HistoryStore) {
        let store = try makeStore(in: directory, texts: texts)
        let model = PanelViewModel(store: store, copier: copier)
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

    @Test("Return copies the selection and closes; ⌘N copies row N")
    func activation() throws {
        defer { removeTemporaryDirectory(directory) }
        let copier = RecordingCopier()
        let (model, _) = try makeModel(["one", "two", "three"], copier: copier)
        var dismissed = 0
        model.onDismiss = { dismissed += 1 }

        model.select(index: 1)
        model.perform(.activate(plainText: true))
        model.perform(.activateRow(2, plainText: false))
        model.perform(.activateRow(8, plainText: false))
        #expect(copier.copies == [
            RecordingCopier.Copy(title: "two", asPlainText: true),
            RecordingCopier.Copy(title: "three", asPlainText: false),
        ])
        #expect(dismissed == 2)
    }

    @Test("A failed copy keeps the panel open and says so")
    func copyFailure() throws {
        defer { removeTemporaryDirectory(directory) }
        let copier = RecordingCopier()
        copier.failure = TestSetupError(description: "nope")
        let (model, _) = try makeModel(["one"], copier: copier)
        var dismissed = false
        model.onDismiss = { dismissed = true }
        model.perform(.activate(plainText: false))
        #expect(!dismissed)
        #expect(model.notice == "Couldn't copy that clip.")
        model.perform(.moveSelection(by: 1))
        #expect(model.notice == nil)
    }

    @Test("Clearing unpinned clips asks first and keeps pins")
    func clearUnpinned() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store) = try makeModel(["one", "two", "three"])
        model.select(index: 2)
        model.perform(.togglePin)

        model.perform(.requestClearUnpinned)
        #expect(model.isConfirmingClear)
        #expect(model.unpinnedCount == 2)
        // Anything but Return backs out without deleting.
        model.perform(.delete)
        #expect(!model.isConfirmingClear)
        #expect(store.recent.count == 2)

        model.perform(.requestClearUnpinned)
        model.perform(.activate(plainText: false))
        #expect(!model.isConfirmingClear)
        #expect(store.recent.isEmpty)
        #expect(titles(model) == ["three"])

        model.perform(.requestClearUnpinned)
        #expect(!model.isConfirmingClear)
        #expect(model.notice == "There are no unpinned clips to clear.")
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
