import Foundation
import Testing
@testable import KeptCore

@MainActor
@Suite("History renaming and editing")
struct HistoryEditingTests {
    let directory: URL

    init() throws {
        directory = try makeTemporaryDirectory()
    }

    private func makeStore(_ limits: HistoryLimits = HistoryLimits()) throws -> HistoryStore {
        try HistoryStore(directory: directory, limits: limits)
    }

    private func draft(_ items: PasteboardItem...) throws -> ClipDraft {
        try #require(ClipBuilder().build(from: PasteboardSnapshot(items: items)))
    }

    private func blobFiles() throws -> [String] {
        let blobs = directory.appendingPathComponent(HistoryStore.blobDirectoryName)
        return try FileManager.default.contentsOfDirectory(atPath: blobs.path).filter { !$0.hasPrefix(".") }
    }

    private func openDatabase() throws -> SQLiteDatabase {
        try SQLiteDatabase(.file(path: directory.appendingPathComponent(HistoryStore.databaseFileName).path))
    }

    // MARK: Migration

    @Test("Opens a history saved before custom titles and adds the column in place")
    func migratesSchemaOne() throws {
        defer { removeTemporaryDirectory(directory) }
        let saved = textDraft("from the first version")
        let id = UUID()
        do {
            let database = try openDatabase()
            try database.execute(HistorySchema.migrations[0])
            try database.setUserVersion(1)
            try database.run(
                """
                INSERT INTO clips (id, kind, title, search_text, content_hash, first_copied_at, last_copied_at,
                                   copy_count, pin_order, byte_size, metadata)
                VALUES (?, 'text', ?, ?, ?, ?, ?, 3, 0, ?, '{"characterCount":22}')
                """,
                .text(id.uuidString), .text(saved.title), .text(saved.searchText), .text(saved.contentHash),
                .real(Date.at(1).timeIntervalSinceReferenceDate), .real(Date.at(2).timeIntervalSinceReferenceDate),
                .int(saved.byteSize)
            )
            try database.run(
                "INSERT INTO representations (clip_id, item_index, position, type, data, size) VALUES (?, 0, 0, ?, ?, ?)",
                .text(id.uuidString), .text(PasteboardType.string.rawValue),
                .blob(Data("from the first version".utf8)), .int(saved.byteSize)
            )
        }

        let store = try makeStore()
        #expect(try openDatabase().userVersion() == HistorySchema.currentVersion)
        #expect(HistorySchema.currentVersion == 2)
        let clip = try #require(store.pinned.first)
        #expect(clip.id == id)
        #expect(clip.customTitle == nil)
        #expect(clip.displayTitle == "from the first version")
        #expect(clip.copyCount == 3)
        #expect(clip.metadata.characterCount == 22)
        #expect(try store.representations(for: id) == [item((.string, "from the first version"))])
        #expect(store.openWarnings.isEmpty)

        try store.rename(id, to: "Old one")
        let reopened = try makeStore()
        #expect(reopened.pinned.first?.customTitle == "Old one")
        #expect(reopened.pinned.first?.copyCount == 3)
    }

    // MARK: Renaming

    @Test("Renames a clip in place; the list shows the name and search finds it")
    func renames() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let a = try store.record(textDraft("Thanks for reaching out"), at: .at(1))
        try store.record(textDraft("same moment"), at: .at(1))
        try store.record(textDraft("newest"), at: .at(2))
        let order = store.recent.map(\.id)

        let renamed = try store.rename(a.id, to: "  Support\nreply  ")
        #expect(renamed.customTitle == "Support reply")
        #expect(renamed.displayTitle == "Support reply")
        #expect(renamed.title == "Thanks for reaching out")
        #expect(renamed.lastCopiedAt == .at(1))
        #expect(store.recent.map(\.id) == order, "renaming doesn't move a clip")
        #expect(store.clip(withID: a.id) == renamed)

        let results = ClipSearch.results(for: "support", pinned: store.pinned, recent: store.recent)
        #expect(results.map(\.id) == [a.id])
        // Content still matches, and one token each from the name and the text.
        #expect(ClipSearch.results(for: "reaching", pinned: store.pinned, recent: store.recent).map(\.id) == [a.id])
        #expect(ClipSearch.results(for: "reply thanks", pinned: store.pinned, recent: store.recent).map(\.id) == [a.id])

        #expect(try makeStore().clip(withID: a.id)?.customTitle == "Support reply")
    }

    @Test("A blank name, nil or the clip's own title clears the name")
    func clearsNames() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let clip = try store.record(textDraft("git log --oneline"), at: .at(1))

        for clearing in [nil, "", "   \n\t", "\u{200B}", "git log --oneline", " git  log --oneline "] as [String?] {
            try store.rename(clip.id, to: "Log")
            #expect(store.clip(withID: clip.id)?.customTitle == "Log")
            let cleared = try store.rename(clip.id, to: clearing)
            #expect(cleared.customTitle == nil, "\(String(describing: clearing))")
            #expect(cleared.displayTitle == "git log --oneline")
        }
        #expect(try makeStore().clip(withID: clip.id)?.customTitle == nil)
        let unknown = UUID()
        #expect(throws: HistoryStoreError.clipNotFound(unknown)) { try store.rename(unknown, to: "x") }
    }

    @Test("Names are sanitized and capped like titles")
    func sanitizesNames() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let clip = try store.record(textDraft("text"), at: .at(1))
        let long = String(repeating: "é", count: 500)
        let renamed = try store.rename(clip.id, to: "A\u{0}B\u{202E}C " + long)
        let name = try #require(renamed.customTitle)
        #expect(name.hasPrefix("ABC é"))
        #expect(name.count == Clip.maxCustomTitleCharacters)
        #expect(!name.contains("\n"))
        let zalgo = "Z" + String(repeating: "\u{0301}", count: 200)
        let capped = try #require(try store.rename(clip.id, to: zalgo).customTitle)
        #expect(capped.unicodeScalars.count <= TextSanitizer.maxScalarsPerCharacter)
    }

    @Test("A re-copy and a pin keep the name")
    func keepsNameThroughRecopies() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let clip = try store.record(textDraft("address"), at: .at(1))
        try store.rename(clip.id, to: "Home")
        try store.pin(clip.id)
        let again = try store.record(textDraft("address"), at: .at(5))
        #expect(again.customTitle == "Home")
        #expect(again.copyCount == 2)
        #expect(again.pinOrder == 0)
        try store.unpin(clip.id, at: .at(6))
        #expect(store.recent.first?.customTitle == "Home")
        #expect(try makeStore().recent.first?.customTitle == "Home")
    }

    // MARK: Editing

    @Test("Editing text keeps the clip's ID, place, pin, name, copies and dates")
    func editsInPlace() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let clip = try store.record(textDraft("Draft reply", source: "com.apple.mail"), at: .at(1))
        try store.record(textDraft("Draft reply", source: "com.apple.mail"), at: .at(2))
        try store.record(textDraft("newer"), at: .at(3))
        try store.pin(clip.id)
        try store.rename(clip.id, to: "Reply")
        let generation = store.clearGeneration

        let edited = try store.editText(clip.id, to: "Final reply, with thanks", at: .at(10))
        #expect(edited.id == clip.id)
        #expect(edited.kind == .text)
        #expect(edited.title == "Final reply, with thanks")
        #expect(edited.searchText == "Final reply, with thanks")
        #expect(edited.customTitle == "Reply")
        #expect(edited.copyCount == 2)
        #expect(edited.pinOrder == 0)
        #expect(edited.firstCopiedAt == .at(1))
        #expect(edited.lastCopiedAt == .at(2))
        #expect(edited.sourceBundleID == "com.apple.mail")
        #expect(edited.metadata.characterCount == 24)
        #expect(edited.contentHash == textDraft("Final reply, with thanks").contentHash)
        #expect(edited.byteSize == 24)
        #expect(store.pinned == [edited])
        #expect(store.recent.map(\.title) == ["newer"])
        #expect(try store.representations(for: clip.id) == [item((.string, "Final reply, with thanks"))])
        #expect(store.clearGeneration == generation, "an edit doesn't drop other captures in flight")
        #expect(ClipSearch.results(for: "thanks", pinned: store.pinned, recent: store.recent).map(\.id) == [clip.id])

        let reopened = try makeStore()
        #expect(reopened.pinned == [edited])
        #expect(try reopened.representations(for: clip.id) == [item((.string, "Final reply, with thanks"))])
    }

    @Test("Editing works the kind out again: text, link and color turn into each other")
    func recomputesKind() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let clip = try store.record(textDraft("plain words"), at: .at(1))

        let link = try store.editText(clip.id, to: "https://kept.app/docs")
        #expect(link.kind == .link)
        #expect(link.metadata.linkHost == "kept.app")

        let color = try store.editText(clip.id, to: "#FF6A00")
        #expect(color.kind == .color)
        #expect(color.metadata.colorHex == "#FF6A00")
        #expect(color.metadata.linkHost == nil)

        let code = try store.editText(clip.id, to: "func go() {\n    run()\n}")
        #expect(code.kind == .text)
        #expect(code.metadata.looksLikeCode)
        #expect(code.metadata.colorHex == nil)
        #expect(code.title == "func go() { run() }")
        #expect(store.recent.map(\.id) == [clip.id])
    }

    @Test("Editing rich text keeps the text and drops the formatting")
    func editsRichText() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let rich = try store.record(
            try draft(item((.rtf, #"{\rtf1\b Hello}"#), (.html, "<b>Hello</b>"), (.string, "Hello"))),
            at: .at(1)
        )
        #expect(rich.kind == .richText)

        let edited = try store.editText(rich.id, to: "Hello there")
        #expect(edited.kind == .text)
        #expect(try store.representations(for: rich.id) == [item((.string, "Hello there"))])

        // The same words saved again still lose the formatting (one plain
        // string), and the content hash stays.
        let again = try store.record(
            try draft(item((.rtf, #"{\rtf1\b Hello there}"#), (.string, "Hello there"))),
            at: .at(2)
        )
        #expect(again.id == rich.id)
        let plain = try store.editText(rich.id, to: "Hello there")
        #expect(plain.contentHash == again.contentHash)
        #expect(plain.kind == .text)
        #expect(!store.wasDeleted(plain.contentHash, after: .at(0)), "unchanged content isn't remembered as deleted")
    }

    @Test("Images and files can't be edited, and the text must show something")
    func rejectsWhatIsntText() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let png = pngData(width: 4, height: 4, byteCount: 100)
        let image = try store.record(try draft(PasteboardItem([ClipRepresentation(.png, png)])), at: .at(1))
        let file = try store.record(try draft(item((.fileURL, "file:///tmp/notes.txt"))), at: .at(2))
        let text = try store.record(textDraft("text"), at: .at(3))

        #expect(throws: HistoryStoreError.notEditable(image.id)) { try store.editText(image.id, to: "x") }
        #expect(throws: HistoryStoreError.notEditable(file.id)) { try store.editText(file.id, to: "x") }
        #expect(throws: HistoryStoreError.emptyText) { try store.editText(text.id, to: " \n\t\u{200B}") }
        let unknown = UUID()
        #expect(throws: HistoryStoreError.clipNotFound(unknown)) { try store.editText(unknown, to: "x") }
        #expect(try store.representations(for: image.id).first?.data(for: .png) == png)
        #expect(store.clip(withID: text.id)?.title == "text")
        let textLike = ClipKind.allCases.filter { $0.isTextLike }
        #expect(textLike == [.text, .richText, .link, .color])
    }

    @Test("Editing big text writes a blob file and deletes the old one")
    func editsBigText() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore(HistoryLimits(inlineThreshold: 64))
        let long = String(repeating: "first draft ", count: 20)
        let clip = try store.record(textDraft(long), at: .at(1))
        #expect(try blobFiles() == [SHA256.hexDigest(of: Data(long.utf8))])

        let longer = String(repeating: "second draft ", count: 20)
        try store.editText(clip.id, to: longer)
        #expect(try blobFiles() == [SHA256.hexDigest(of: Data(longer.utf8))])
        #expect(try store.representations(for: clip.id) == [item((.string, longer))])

        try store.editText(clip.id, to: "short")
        #expect(try blobFiles().isEmpty)
    }

    // MARK: Merging

    @Test("Editing into another clip's content merges the two into the edited one")
    func mergesDuplicates() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let edited = try store.record(textDraft("teh plan"), at: .at(1))
        let other = try store.record(textDraft("the plan", source: "com.apple.Notes"), at: .at(2))
        try store.record(textDraft("the plan"), at: .at(3))
        try store.record(textDraft("newest"), at: .at(4))
        try store.rename(other.id, to: "Plan")

        let merged = try store.editText(edited.id, to: "the plan", at: .at(10))
        #expect(merged.id == edited.id)
        #expect(merged.copyCount == 3)
        #expect(merged.firstCopiedAt == .at(1))
        #expect(merged.lastCopiedAt == .at(3), "the later copy, so it isn't forgotten early")
        #expect(merged.customTitle == "Plan", "the other's name, since it had none")
        #expect(store.clip(withID: other.id) == nil)
        #expect(store.recent.map(\.title) == ["newest", "the plan"])
        #expect(store.recent.last?.id == edited.id)
        #expect(!store.wasDeleted(merged.contentHash, after: .at(0)), "the content lives on")
        #expect(try openDatabase().scalarInt("SELECT COUNT(*) FROM clips") == 2)
        #expect(try makeStore().recent.map(\.id) == store.recent.map(\.id))
    }

    @Test("A merge carries over the other clip's pin")
    func mergesPins() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let first = try store.record(textDraft("first pin"), at: .at(1))
        let target = try store.record(textDraft("target"), at: .at(2))
        let last = try store.record(textDraft("last pin"), at: .at(3))
        let edited = try store.record(textDraft("edit me"), at: .at(4))
        for id in [first.id, target.id, last.id] { try store.pin(id) }

        // Unpinned, edited into a pin's content: it takes that pin's place.
        let merged = try store.editText(edited.id, to: "target")
        #expect(merged.pinOrder == 1)
        #expect(store.pinned.map(\.id) == [first.id, edited.id, last.id])
        #expect(store.pinned.map(\.pinOrder) == [0, 1, 2])
        #expect(store.recent.isEmpty)
        #expect(try makeStore().pinned.map(\.id) == [first.id, edited.id, last.id])
    }

    @Test("Two pins merge into the edited one, which keeps its own place")
    func mergesTwoPins() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let a = try store.record(textDraft("a"), at: .at(1))
        let b = try store.record(textDraft("b"), at: .at(2))
        let c = try store.record(textDraft("c"), at: .at(3))
        let loose = try store.record(textDraft("loose"), at: .at(4))
        for id in [a.id, b.id, c.id] { try store.pin(id) }
        try store.rename(c.id, to: "Kept name")
        try store.rename(a.id, to: "Other name")

        let merged = try store.editText(c.id, to: "a")
        #expect(merged.pinOrder == 1)
        #expect(merged.customTitle == "Kept name")
        #expect(store.pinned.map(\.id) == [b.id, c.id])
        #expect(store.pinned.map(\.pinOrder) == [0, 1])
        #expect(store.recent.map(\.id) == [loose.id])

        // A pinned clip edited into an unpinned one's content stays put.
        let again = try store.editText(b.id, to: "loose")
        #expect(again.pinOrder == 0)
        #expect(store.pinned.map(\.id) == [b.id, c.id])
        #expect(store.recent.isEmpty)
        let reopened = try makeStore()
        #expect(reopened.pinned.map(\.id) == [b.id, c.id])
        #expect(reopened.pinned.map(\.pinOrder) == [0, 1])
    }

    // MARK: Captures in flight

    @Test("A copy of the old text seen before the edit can't come back; one made after can")
    func remembersEditedAwayContent() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let clip = try store.record(textDraft("old words"), at: .at(1))
        let oldHash = clip.contentHash
        try store.editText(clip.id, to: "new words", at: .at(10))

        // What capture asks before recording a finished build.
        #expect(store.wasDeleted(oldHash, after: .at(9)), "copied before the edit: dropped")
        #expect(!store.wasDeleted(oldHash, after: .at(11)), "copied again after the edit: kept")
        let recopied = try store.record(textDraft("old words"), at: .at(11))
        #expect(recopied.id != clip.id)
        #expect(store.recent.map(\.title) == ["old words", "new words"])
    }

    @Test("A capture of the new text staged before the edit lands on the edited clip")
    func inFlightCaptureOfNewText() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore(HistoryLimits(inlineThreshold: 64))
        let text = String(repeating: "shared text ", count: 10)
        let staged = try store.stager.stage(textDraft(text))
        let clip = try store.record(textDraft("draft"), at: .at(1))
        try store.pin(clip.id)
        try store.rename(clip.id, to: "Name")
        let generation = store.clearGeneration

        try store.editText(clip.id, to: text, at: .at(5))
        #expect(store.clearGeneration == generation)
        #expect(!store.wasDeleted(staged.draft.contentHash, after: .at(4)))
        let recorded = try store.record(staged, at: .at(6))
        #expect(recorded.id == clip.id)
        #expect(recorded.customTitle == "Name")
        #expect(recorded.pinOrder == 0)
        #expect(recorded.copyCount == 2)
        #expect(try blobFiles() == [SHA256.hexDigest(of: Data(text.utf8))])
        #expect(try store.representations(for: clip.id) == [item((.string, text))])
    }

    @Test("Clearing the history still drops captures seen before it, edit or not")
    func clearGenerationStillCounts() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let clip = try store.record(textDraft("one"), at: .at(1))
        let seen = store.clearGeneration
        try store.editText(clip.id, to: "two")
        try store.rename(clip.id, to: "Name")
        #expect(store.clearGeneration == seen)
        try store.clearUnpinned()
        #expect(store.clearGeneration == seen + 1)
    }
}
