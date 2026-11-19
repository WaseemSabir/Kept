import Foundation
import Testing
@testable import Kept
import KeptCore

@MainActor
@Suite("Panel renaming and editing")
struct PanelEditingTests {
    private typealias Key = PanelKeyRouter.KeyCode
    let directory: URL

    init() throws {
        directory = try makeTemporaryDirectory()
    }

    /// "one", "two", "three", newest first, the first one selected.
    private func makeModel(
        _ texts: [String] = ["one", "two", "three"]
    ) throws -> (PanelViewModel, HistoryStore, RecordingPaster) {
        let store = try makeStore(in: directory, texts: texts)
        let paster = RecordingPaster()
        let model = PanelViewModel(store: store, paster: paster)
        model.prepareForShow()
        return (model, store, paster)
    }

    /// Routes a key press the way the panel does; `false` when the key goes
    /// on to the field with the keyboard.
    @discardableResult
    private func press(
        _ model: PanelViewModel,
        _ keyCode: UInt16,
        _ modifiers: KeyPress.Modifiers = [],
        _ characters: String = ""
    ) -> Bool {
        let keyPress = KeyPress(keyCode: keyCode, modifiers: modifiers, characters: characters)
        guard let command = PanelKeyRouter.command(for: keyPress, mode: model.keyMode) else { return false }
        return model.perform(command)
    }

    @discardableResult
    private func record(_ draft: ClipDraft, in store: HistoryStore, at seconds: Double = 100) throws -> Clip {
        try store.record(draft, at: .at(seconds))
    }

    private func draft(_ items: PasteboardItem...) throws -> ClipDraft {
        guard let draft = ClipBuilder().build(from: PasteboardSnapshot(items: items)) else {
            throw TestSetupError(description: "No draft for \(items)")
        }
        return draft
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<400 where !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: Renaming

    @Test("⌘R names the selected clip in its row; ⏎ saves and the search field gets the keyboard back")
    func renames() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store, _) = try makeModel()
        var messages: [String] = []
        model.announce = { messages.append($0) }
        model.select(index: 1)

        #expect(press(model, 15, .command, "r"))
        #expect(model.keyMode == .renaming)
        #expect(model.renamingID == model.selectedID)
        #expect(model.nameDraft == "two")
        let focus = model.searchFocusToken

        model.nameDraft = "Second"
        #expect(press(model, Key.returnKey))
        #expect(model.editing == nil)
        #expect(model.keyMode == .browsing)
        #expect(model.searchFocusToken == focus + 1)
        #expect(store.recent.map(\.displayTitle) == ["one", "Second", "three"])
        #expect(model.selectedClip?.displayTitle == "Second")
        #expect(model.selectedIndex == 1)
        #expect(messages == ["Renamed to Second."])

        // Prefilled with the name next time; empty brings the text back.
        model.perform(.beginRename)
        #expect(model.nameDraft == "Second")
        model.nameDraft = "   "
        model.perform(.commitEditing)
        #expect(store.recent[1].customTitle == nil)
        #expect(messages.last == "Name removed. The clip shows its text.")
    }

    @Test("Esc cancels the rename, not the panel; a second Esc closes it")
    func escapeCancelsRename() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store, _) = try makeModel()
        var dismissed = 0
        model.onDismiss = { dismissed += 1 }
        model.perform(.beginRename)
        model.nameDraft = "Changed"
        let focus = model.searchFocusToken

        #expect(press(model, Key.escape))
        #expect(dismissed == 0)
        #expect(model.editing == nil)
        #expect(model.searchFocusToken == focus + 1)
        #expect(store.recent.allSatisfy { $0.customTitle == nil })

        #expect(press(model, Key.escape))
        #expect(dismissed == 1)
    }

    @Test("List shortcuts do nothing while renaming; typing and editing keys reach the field")
    func renamingSuppressesShortcuts() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store, paster) = try makeModel()
        var settingsOpened = 0
        model.onOpenSettings = { settingsOpened += 1 }
        model.perform(.beginRename)
        let renaming = model.editing

        #expect(press(model, 18, .command, "1"))
        #expect(press(model, 19, [.command, .option], "2"))
        #expect(press(model, 35, .command, "p"))
        #expect(press(model, 43, .command, ","))
        #expect(press(model, 14, .command, "e"))
        #expect(press(model, Key.returnKey, .option))
        #expect(press(model, Key.tab))
        #expect(!press(model, Key.delete, .command), "⌘⌫ deletes in the name")
        #expect(!press(model, Key.delete, [.command, .option]))
        #expect(!press(model, Key.downArrow), "↓ moves the caret")
        #expect(!press(model, 0, [], "a"))
        #expect(!press(model, 0, .command, "a"), "⌘A goes to the name field")

        #expect(model.editing == renaming)
        #expect(paster.pastes.isEmpty)
        #expect(store.pinned.isEmpty)
        #expect(store.recent.count == 3)
        #expect(settingsOpened == 0)
        #expect(model.selectedIndex == 0)
        #expect(model.filter == .all)
        #expect(!model.isConfirmingClear)
    }

    @Test("Clicking another row, searching or closing the panel saves the name")
    func movingAwaySavesTheName() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store, _) = try makeModel()

        model.perform(.beginRename)
        model.nameDraft = "First"
        // A click inside the field selects the same row: still renaming.
        model.select(model.results[0])
        #expect(model.renamingID != nil)
        model.select(model.results[2])
        #expect(model.editing == nil)
        #expect(store.recent[0].customTitle == "First")
        #expect(model.selectedClip?.title == "three")

        model.perform(.beginRename)
        model.nameDraft = "Third"
        model.query = "th"
        #expect(model.editing == nil)
        #expect(store.recent[2].customTitle == "Third")

        model.query = ""
        model.select(index: 1)
        model.perform(.beginRename)
        model.nameDraft = "Hidden"
        model.panelDidHide()
        #expect(model.editing == nil)
        #expect(store.recent[1].customTitle == "Hidden")
    }

    @Test("The name field losing the keyboard saves only its own clip's name")
    func resigningSaves() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store, _) = try makeModel()
        let first = try #require(model.selectedClip)
        model.perform(.beginRename)
        model.nameDraft = "Kept"
        model.renameFieldDidResign(for: UUID())
        #expect(model.renamingID == first.id)
        model.renameFieldDidResign(for: first.id)
        #expect(model.editing == nil)
        #expect(store.clip(withID: first.id)?.customTitle == "Kept")
    }

    @Test("The context menu's Rename… saves a name being typed in another row first")
    func contextMenuRename() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store, _) = try makeModel()
        model.perform(.beginRename)
        model.nameDraft = "Alpha"
        let third = model.results[2]
        model.perform(.beginRename, on: third)
        #expect(store.recent[0].customTitle == "Alpha")
        #expect(model.renamingID == third.id)
        #expect(model.nameDraft == "three")
    }

    @Test("A clip that goes away while it's renamed stops the rename")
    func vanishingClipEndsRename() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store, _) = try makeModel()
        let clip = try #require(model.selectedClip)
        model.perform(.beginRename)
        try store.delete(clip.id)
        model.refresh()
        #expect(model.editing == nil)
        #expect(model.keyMode == .browsing)
    }

    // MARK: Editing text

    @Test("⌘E edits a text clip in the preview; ⌘S saves it in place and keeps it selected")
    func editsText() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store, _) = try makeModel(["alpha", "beta"])
        var messages: [String] = []
        model.announce = { messages.append($0) }
        model.select(index: 1)

        #expect(press(model, 14, .command, "e"))
        #expect(model.keyMode == .editingText)
        let edit = try #require(model.textEdit)
        #expect(edit.clipID == model.selectedID)
        #expect(edit.original == "beta")
        #expect(!edit.dropsFormatting)
        #expect(!edit.isCode)
        #expect(model.textDraft == "beta")

        model.textDraft = "beta, edited"
        #expect(!press(model, Key.returnKey), "⏎ types a line break")
        #expect(!press(model, Key.tab), "Tab types a tab")
        let focus = model.searchFocusToken
        #expect(press(model, 1, .command, "s"))
        #expect(model.editing == nil)
        #expect(model.searchFocusToken == focus + 1)
        #expect(model.selectedClip?.title == "beta, edited")
        #expect(model.selectedIndex == 1)
        #expect(store.recent.map(\.title) == ["alpha", "beta, edited"])
        #expect(messages == ["Edit saved."])
        let clip = try #require(model.selectedClip)
        #expect(model.preview(for: clip).content == .text("beta, edited", isCode: false))
    }

    @Test("⌘⏎ saves too; Esc puts the text back without closing the panel")
    func commandReturnAndEscape() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store, _) = try makeModel()
        var dismissed = 0
        model.onDismiss = { dismissed += 1 }

        model.perform(.beginTextEdit)
        model.textDraft = "one!"
        #expect(press(model, Key.returnKey, .command))
        #expect(store.recent[0].title == "one!")

        model.perform(.beginTextEdit)
        model.textDraft = "one?"
        #expect(press(model, Key.escape))
        #expect(model.editing == nil)
        #expect(dismissed == 0)
        #expect(store.recent[0].title == "one!")
    }

    @Test("List shortcuts do nothing while editing text")
    func editingSuppressesShortcuts() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store, paster) = try makeModel()
        model.perform(.beginTextEdit)
        let editing = model.editing

        #expect(press(model, 18, .command, "1"))
        #expect(press(model, 35, .command, "p"))
        #expect(press(model, 15, .command, "r"))
        #expect(press(model, Key.tab, .shift))
        #expect(!press(model, Key.delete, .command), "⌘⌫ deletes in the text")
        #expect(!press(model, Key.upArrow, .command), "⌘↑ moves to the start of the text")
        #expect(model.editing == editing)
        #expect(paster.pastes.isEmpty)
        #expect(store.pinned.isEmpty)
        #expect(model.selectedIndex == 0)
    }

    @Test("Saving the text unchanged changes nothing")
    func unchangedSaveIsNoOp() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store, _) = try makeModel()
        let rich = try record(try draft(PasteboardItem([
            ClipRepresentation(.rtf, string: #"{\rtf1\b Bold words}"#), ClipRepresentation(.string, string: "Bold words"),
        ])), in: store)
        model.refresh(selecting: .first)
        #expect(model.selectedClip?.id == rich.id)

        model.perform(.beginTextEdit)
        #expect(model.textEdit?.dropsFormatting == true)
        model.perform(.commitEditing)
        #expect(model.editing == nil)
        #expect(store.clip(withID: rich.id) == rich)
        #expect(try store.representations(for: rich.id).first?.data(for: .rtf) != nil)
    }

    @Test("Rich text is edited as its text, and saving drops the formatting")
    func editsRichText() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store, _) = try makeModel()
        let rich = try record(try draft(PasteboardItem([
            ClipRepresentation(.rtf, string: #"{\rtf1\b Hello}"#), ClipRepresentation(.string, string: "Hello"),
        ])), in: store)
        model.refresh(selecting: .first)
        model.perform(.beginTextEdit)
        #expect(model.textEdit?.dropsFormatting == true)
        #expect(model.textDraft == "Hello")
        model.textDraft = "Hello there"
        model.perform(.commitEditing)
        let edited = try #require(store.clip(withID: rich.id))
        #expect(edited.kind == .text)
        #expect(try store.representations(for: rich.id) == [PasteboardItem([ClipRepresentation(.string, string: "Hello there")])])
    }

    @Test("Code, links and colors are edited in monospace; text can turn into a link")
    func editsCodeLinksAndColors() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store, _) = try makeModel(["plain words", "https://kept.app", "#FF6A00", "func go() {\n    run()\n}"])
        let kinds = model.results.map { PanelViewModel.editsAsCode($0) }
        #expect(kinds == [false, true, true, true])

        model.select(index: 0)
        model.perform(.beginTextEdit)
        model.textDraft = "https://kept.app/docs"
        model.perform(.commitEditing)
        #expect(store.recent[0].kind == .link)
        #expect(model.selectedClip?.kind == .link)
    }

    @Test("Images and files can't be edited: the footer says to rename them instead")
    func refusesImagesAndFiles() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store, _) = try makeModel()
        var messages: [String] = []
        model.announce = { messages.append($0) }
        let png = try encodedImage(width: 4, height: 4, type: "public.png")
        let image = try record(try draft(PasteboardItem([ClipRepresentation(.png, png)])), in: store, at: 100)
        let files = try record(try draft(
            PasteboardItem([ClipRepresentation(.fileURL, string: "file:///tmp/a.txt")]),
            PasteboardItem([ClipRepresentation(.fileURL, string: "file:///tmp/b.txt")])
        ), in: store, at: 101)
        model.refresh(selecting: .first)

        #expect(model.selectedClip?.id == files.id)
        model.perform(.beginTextEdit)
        #expect(model.editing == nil)
        #expect(model.notice == "Only text can be edited. Press ⌘R to rename these files.")

        model.select(model.results[1])
        #expect(model.selectedClip?.id == image.id)
        #expect(press(model, 14, .command, "e"))
        #expect(model.editing == nil)
        #expect(model.notice == "Only text can be edited. Press ⌘R to rename this image.")
        #expect(messages.last == model.notice)

        // ⌘R still names them.
        model.perform(.beginRename)
        model.nameDraft = "Sunset"
        model.perform(.commitEditing)
        #expect(store.clip(withID: image.id)?.displayTitle == "Sunset")
    }

    @Test("Saving empty text keeps the editor open with a notice; moving away drops it")
    func emptyText() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store, _) = try makeModel()
        model.perform(.beginTextEdit)
        model.textDraft = "  \n "
        model.perform(.commitEditing)
        #expect(model.textEdit != nil)
        #expect(model.notice == "Type some text to save, or press Esc to cancel.")
        #expect(store.recent[0].title == "one")

        model.select(model.results[1])
        #expect(model.editing == nil)
        #expect(store.recent[0].title == "one")
        #expect(model.notice == "An empty edit wasn't saved.")
    }

    @Test("Closing the panel saves the text being edited")
    func hidingSavesText() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store, _) = try makeModel()
        model.perform(.beginTextEdit)
        model.textDraft = "one, saved on close"
        model.panelDidHide()
        #expect(model.editing == nil)
        #expect(store.recent[0].title == "one, saved on close")
    }

    @Test("Double-clicking the clip being edited saves it first, so it pastes as edited")
    func pastesTheEditedText() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, _, paster) = try makeModel()
        let clip = try #require(model.selectedClip)
        model.perform(.beginTextEdit)
        model.textDraft = "one, edited"
        model.activate(clip)
        #expect(paster.pastes.map(\.title) == ["one, edited"])
    }

    @Test("A clip too long to edit says how long Kept goes")
    func refusesTooLongText() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store, _) = try makeModel()
        let long = String(repeating: "a", count: PanelViewModel.maxEditableCharacters + 1)
        try record(try textDraft(long), in: store)
        model.refresh(selecting: .first)
        model.perform(.beginTextEdit)
        #expect(model.editing == nil)
        #expect(model.notice == "Kept edits clips of up to 100,000 characters.")
    }

    @Test("A big clip's text is read off the main actor, then edited")
    func loadsBigTextFirst() async throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store, _) = try makeModel()
        let big = String(repeating: "word ", count: 14_000)  // 70,000 characters, a blob file
        try record(try textDraft(big), in: store)
        model.refresh(selecting: .first)
        model.perform(.beginTextEdit)
        try await waitUntil { model.textEdit != nil }
        #expect(model.textDraft == big)
        #expect(model.keyMode == .editingText)
    }

    // MARK: Menus, facts and VoiceOver

    @Test("The context menu offers Rename… for every clip and Edit… only for text")
    func contextMenuPerKind() throws {
        defer { removeTemporaryDirectory(directory) }
        func clip(_ kind: ClipKind, pinned: Bool = false) -> Clip {
            Clip(kind: kind, title: "x", searchText: "x", contentHash: "h", firstCopiedAt: .at(0), lastCopiedAt: .at(0),
                 pinOrder: pinned ? 0 : nil, byteSize: 1)
        }
        func titles(_ clip: Clip, copyOnly: String? = "Copy") -> [[String]] {
            ClipMenu.sections(for: clip, primaryTitle: "Paste", alternateTitle: "Paste as plain text", copyOnlyTitle: copyOnly)
                .map { $0.map(\.title) }
        }
        for kind in [ClipKind.text, .richText, .link, .color] {
            #expect(titles(clip(kind)) == [["Paste", "Paste as plain text", "Copy"], ["Pin", "Rename…", "Edit…"], ["Delete"]])
        }
        for kind in [ClipKind.image, .file] {
            #expect(titles(clip(kind)) == [["Paste", "Paste as plain text", "Copy"], ["Pin", "Rename…"], ["Delete"]])
        }
        #expect(titles(clip(.text, pinned: true), copyOnly: nil) == [
            ["Paste", "Paste as plain text"], ["Unpin", "Rename…", "Edit…"], ["Delete"],
        ])
        let commands = ClipMenu.sections(for: clip(.text), primaryTitle: "P", alternateTitle: "A", copyOnlyTitle: nil)
            .flatMap { $0.map(\.command) }
        #expect(commands == [.activate(alternate: false), .activate(alternate: true), .togglePin, .beginRename, .beginTextEdit, .delete])
    }

    @Test("A named clip's facts end with what it holds; VoiceOver reads the name")
    func namedClipFactsAndLabel() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store, _) = try makeModel(["Thanks for reaching out!\nWe'll reply soon."])
        let clip = try store.rename(store.recent[0].id, to: "Support reply")
        let preview = PreviewLoader.textPreview("\n  Thanks for reaching out!\nWe'll reply soon.", isCode: false)
        let facts = model.facts(for: clip, preview: preview)
        #expect(facts.last == ClipFact(label: "Content", value: "Thanks for reaching out!", truncatesTail: true))
        #expect(ClipAccessibility.label(for: clip, appName: nil, now: .at(0)).hasPrefix("Text, Support reply, "))

        let unnamed = try store.rename(clip.id, to: nil)
        #expect(!model.facts(for: unnamed, preview: preview).contains { $0.label == "Content" })
        let long = String(repeating: "x", count: 300)
        let cut = ClipFacts.contentLine(of: clip, preview: ClipPreview(.text(long, isCode: false)))
        #expect(cut.count == ClipFacts.maxContentCharacters + 1)
        #expect(cut.hasSuffix("…"))
        // A named image keeps its name; the generated "Image …" isn't trimmed.
        let image = Clip(kind: .image, title: "Image 10 × 10", customTitle: "Image of the sunset", searchText: "",
                         contentHash: "i", firstCopiedAt: .at(0), lastCopiedAt: .at(0), byteSize: 1)
        #expect(ClipAccessibility.spokenTitle(of: image) == "Image of the sunset")
    }
}
