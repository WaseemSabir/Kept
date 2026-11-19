import Foundation
import Testing
@testable import KeptCore

/// Loading chosen representations, and blob files written off the main
/// actor before a clip is recorded.
@MainActor
@Suite("History payloads")
struct HistoryPayloadTests {
    let directory: URL

    init() throws {
        directory = try makeTemporaryDirectory()
    }

    private func makeStore() throws -> HistoryStore {
        try HistoryStore(directory: directory, limits: HistoryLimits(inlineThreshold: 64))
    }

    private var blobDirectory: URL {
        directory.appendingPathComponent(HistoryStore.blobDirectoryName)
    }

    private func blobFiles() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: blobDirectory.path).filter { !$0.hasPrefix(".") })
    }

    private func draft(_ representations: ClipRepresentation...) throws -> ClipDraft {
        try #require(ClipBuilder().build(from: PasteboardSnapshot(items: [PasteboardItem(representations)])))
    }

    private func imageDraft(seed: UInt8 = 0) throws -> (draft: ClipDraft, hash: String) {
        let png = pngData(width: 8, height: 8, byteCount: 400, seed: seed)
        return (try draft(ClipRepresentation(.png, png)), SHA256.hexDigest(of: png))
    }

    // MARK: Chosen types

    @Test("Loads only the types asked for, without reading other blob files")
    func loadsChosenTypes() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let picture = pngData(width: 5, height: 5, byteCount: 400)
        let rtf = #"{\rtf1 Quarterly numbers}"#
        let clip = try store.record(try draft(
            ClipRepresentation(.string, string: "Quarterly numbers"),
            ClipRepresentation(.rtf, string: rtf),
            ClipRepresentation(.png, picture)
        ))

        let text = try store.storedRepresentations(for: clip.id, types: [.string, .rtf])
        #expect(text.entries.map(\.type) == [.string, .rtf])
        #expect(text.isInMemory)
        #expect(text.byteSize == "Quarterly numbers".utf8.count + rtf.utf8.count)

        let image = try store.storedRepresentations(for: clip.id).first(ofAny: [.tiff, .png])
        #expect(image.entries.map(\.type) == [.png])
        #expect(!image.isInMemory)
        #expect(image.byteSize == 400)
        #expect(try image.load() == [PasteboardItem([ClipRepresentation(.png, picture)])])
        #expect(try store.storedRepresentations(for: clip.id).first(ofAny: [.tiff]).isEmpty)
        #expect(try store.storedRepresentations(for: clip.id, types: []).isEmpty)

        // With the picture's file gone, the text still loads; everything doesn't.
        try FileManager.default.removeItem(at: blobDirectory.appendingPathComponent(SHA256.hexDigest(of: picture)))
        #expect(try store.representations(for: clip.id, types: [.string]) == [item((.string, "Quarterly numbers"))])
        #expect(throws: HistoryStoreError.missingBlob(hash: SHA256.hexDigest(of: picture))) {
            try store.representations(for: clip.id)
        }
        let unknown = UUID()
        #expect(throws: HistoryStoreError.clipNotFound(unknown)) {
            try store.storedRepresentations(for: unknown, types: [.string])
        }
    }

    @Test("Leaves out items without the types asked for, keeping the order")
    func chosenTypesAcrossItems() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let items = [
            item((.fileURL, "file:///a.txt"), (.string, "a.txt")),
            item((.fileURL, "file:///b")),
            item((.fileURL, "file:///c.txt"), (.string, "c.txt")),
        ]
        let draft = try #require(ClipBuilder().build(from: PasteboardSnapshot(items: items)))
        let clip = try store.record(draft)
        #expect(try store.representations(for: clip.id, types: [.string]) == [item((.string, "a.txt")), item((.string, "c.txt"))])
        #expect(try store.representations(for: clip.id, types: [.fileURL]).count == 3)
        #expect(try store.representations(for: clip.id) == items)
    }

    // MARK: Staged blob files

    @Test("Stages blob files off the main actor, then records the clip")
    func stagesOffTheMainActor() async throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let (draft, hash) = try imageDraft()
        let stager = store.stager

        let staged = try await Task.detached { try stager.stage(draft) }.value
        #expect(try blobFiles() == [hash])
        #expect(staged.draft.items.first?.representations.first?.sha256 == hash)

        let clip = try store.record(staged, at: .at(1))
        #expect(try store.representations(for: clip.id) == draft.items)
        #expect(store.recent.map(\.id) == [clip.id])
    }

    @Test("A staged blob survives clearing the history until it's recorded")
    func stagedBlobSurvivesClear() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let (draft, hash) = try imageDraft()
        let staged = try store.stager.stage(draft)

        try store.clearAll()
        #expect(try blobFiles() == [hash])
        let clip = try store.record(staged, at: .at(1))
        #expect(try store.representations(for: clip.id) == draft.items)
    }

    @Test("A staged blob survives deleting the clip that shared it")
    func stagedBlobSurvivesDelete() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let (draft, hash) = try imageDraft()
        let old = try store.record(draft, at: .at(1))
        let staged = try store.stager.stage(draft)

        try store.delete(old.id)
        #expect(try blobFiles() == [hash])
        let clip = try store.record(staged, at: .at(2))
        #expect(try store.representations(for: clip.id) == draft.items)
    }

    @Test("Discarding a staged clip deletes its files unless a clip uses them")
    func discardsStagedClips() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let (draft, hash) = try imageDraft()

        store.discard(try store.stager.stage(draft))
        #expect(try blobFiles().isEmpty)

        try store.record(draft, at: .at(1))
        store.discard(try store.stager.stage(draft))
        #expect(try blobFiles() == [hash])
    }

    @Test("Two staged copies of one blob keep it until both are done")
    func overlappingStages() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let (draft, hash) = try imageDraft()
        let first = try store.stager.stage(draft)
        let second = try store.stager.stage(draft)

        store.discard(first)
        try store.clearAll()
        #expect(try blobFiles() == [hash])
        store.discard(second)
        #expect(try blobFiles().isEmpty)
    }

    @Test("A dropped staged clip no longer holds its files back")
    func droppedStageReleases() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let (draft, _) = try imageDraft()
        do {
            _ = try store.stager.stage(draft)
        }
        try store.clearAll()
        #expect(try blobFiles().isEmpty)
    }

    @Test("Writes a staged blob again if its file went missing")
    func rewritesMissingStagedBlob() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let (draft, hash) = try imageDraft()
        let staged = try store.stager.stage(draft)
        try FileManager.default.removeItem(at: blobDirectory.appendingPathComponent(hash))

        let clip = try store.record(staged, at: .at(1))
        #expect(try blobFiles() == [hash])
        #expect(try store.representations(for: clip.id) == draft.items)
    }

    @Test("Counts clears")
    func countsClears() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        #expect(store.clearGeneration == 0)
        try store.record(textDraft("one"))
        try store.clearUnpinned()
        #expect(store.clearGeneration == 1)
        try store.clearAll()
        #expect(store.clearGeneration == 2)
    }
}
