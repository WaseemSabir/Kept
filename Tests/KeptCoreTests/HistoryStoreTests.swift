import Foundation
import Observation
import Testing
@testable import KeptCore

@MainActor
@Suite("History store")
struct HistoryStoreTests {
    let directory: URL

    init() throws {
        directory = try makeTemporaryDirectory()
    }

    private func makeStore(_ limits: HistoryLimits = HistoryLimits()) throws -> HistoryStore {
        try HistoryStore(directory: directory, limits: limits)
    }

    private func blobFiles() throws -> [String] {
        let blobs = directory.appendingPathComponent(HistoryStore.blobDirectoryName)
        return try FileManager.default.contentsOfDirectory(atPath: blobs.path).filter { !$0.hasPrefix(".") }
    }

    private func imageDraft(byteCount: Int, seed: UInt8 = 0) throws -> ClipDraft {
        let png = pngData(width: 10, height: 10, byteCount: byteCount, seed: seed)
        let snapshot = PasteboardSnapshot(items: [PasteboardItem([ClipRepresentation(.png, png)])])
        return try #require(ClipBuilder().build(from: snapshot))
    }

    // MARK: Recording

    @Test("Records clips newest first")
    func recordsNewestFirst() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let first = try store.record(textDraft("first", source: "com.apple.Notes"), at: .at(1))
        try store.record(textDraft("second"), at: .at(2))

        #expect(store.recent.map(\.title) == ["second", "first"])
        #expect(store.pinned.isEmpty)
        #expect(first.firstCopiedAt == .at(1))
        #expect(first.lastCopiedAt == .at(1))
        #expect(first.copyCount == 1)
        #expect(first.sourceBundleID == "com.apple.Notes")
        #expect(store.clip(withID: first.id) == first)
    }

    @Test("Moves a re-copied clip to the top and counts the copy")
    func dedupsRecopies() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let original = try store.record(textDraft("Hello", source: "com.apple.Terminal"), at: .at(1))
        try store.record(textDraft("Other"), at: .at(2))

        let rich = try #require(ClipBuilder().build(from: PasteboardSnapshot(
            items: [item((.rtf, #"{\rtf1\b Hello}"#), (.string, "Hello"))],
            sourceBundleID: "com.apple.TextEdit"
        )))
        let again = try store.record(rich, at: .at(3))

        #expect(store.recent.map(\.title) == ["Hello", "Other"])
        #expect(store.recent.count == 2)
        #expect(again.id == original.id)
        #expect(again.copyCount == 2)
        #expect(again.firstCopiedAt == .at(1))
        #expect(again.lastCopiedAt == .at(3))
        #expect(again.kind == .richText)
        #expect(again.sourceBundleID == "com.apple.TextEdit")
        #expect(try store.representations(for: again.id) == rich.items)
    }

    @Test("Moves a pasted clip to the top without counting a copy")
    func marksUsed() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let old = try store.record(textDraft("old"), at: .at(1))
        try store.record(textDraft("new"), at: .at(2))

        try store.markUsed(old.id, at: .at(3))

        #expect(store.recent.map(\.title) == ["old", "new"])
        #expect(store.recent[0].lastCopiedAt == .at(3))
        #expect(store.recent[0].copyCount == 1)
        let unknown = UUID()
        #expect(throws: HistoryStoreError.clipNotFound(unknown)) { try store.markUsed(unknown) }
    }

    @Test("Notifies observers when the history changes")
    func notifiesObservers() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        final class Flag: @unchecked Sendable { var raised = false }
        let flag = Flag()
        withObservationTracking { _ = store.recent } onChange: { flag.raised = true }

        try store.record(textDraft("hi"))
        #expect(flag.raised)
    }

    // MARK: Pins

    @Test("Pins, reorders and unpins clips")
    func managesPins() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let a = try store.record(textDraft("a"), at: .at(1))
        let b = try store.record(textDraft("b"), at: .at(2))
        let c = try store.record(textDraft("c"), at: .at(3))

        try store.pin(b.id)
        try store.pin(a.id)
        try store.pin(a.id)  // already pinned
        #expect(store.pinned.map(\.title) == ["b", "a"])
        #expect(store.pinned.map(\.pinOrder) == [0, 1])
        #expect(store.recent.map(\.title) == ["c"])
        #expect(store.pinned.allSatisfy { $0.isPinned })

        try store.movePin(a.id, toIndex: 0)
        #expect(store.pinned.map(\.title) == ["a", "b"])
        try store.movePin(a.id, toIndex: 99)
        #expect(store.pinned.map(\.title) == ["b", "a"])
        try store.movePin(c.id, toIndex: 0)  // not pinned: no change
        #expect(store.pinned.map(\.title) == ["b", "a"])

        try store.unpin(b.id)
        #expect(store.pinned.map(\.title) == ["a"])
        #expect(store.pinned.map(\.pinOrder) == [0])
        #expect(store.recent.map(\.title) == ["c", "b"])
        #expect(store.recent.allSatisfy { !$0.isPinned })
        try store.unpin(c.id)  // not pinned
        #expect(throws: HistoryStoreError.self) { try store.pin(UUID()) }
    }

    @Test("Keeps a re-copied pin in place")
    func recopiedPinStaysPinned() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let first = try store.record(textDraft("first"), at: .at(1))
        let second = try store.record(textDraft("second"), at: .at(2))
        try store.pin(first.id)
        try store.pin(second.id)

        let again = try store.record(textDraft("first"), at: .at(3))
        #expect(again.pinOrder == 0)
        #expect(store.pinned.map(\.title) == ["first", "second"])
        #expect(store.pinned[0].copyCount == 2)
        #expect(store.recent.isEmpty)
    }

    // MARK: Removing

    @Test("Deletes clips and renumbers the pins")
    func deletesClips() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let a = try store.record(textDraft("a"), at: .at(1))
        let b = try store.record(textDraft("b"), at: .at(2))
        let c = try store.record(textDraft("c"), at: .at(3))
        try store.pin(a.id)
        try store.pin(b.id)

        try store.delete(a.id)
        try store.delete(c.id)
        #expect(store.pinned.map(\.title) == ["b"])
        #expect(store.pinned.map(\.pinOrder) == [0])
        #expect(store.recent.isEmpty)
        #expect(throws: HistoryStoreError.clipNotFound(a.id)) { try store.delete(a.id) }
        #expect(throws: HistoryStoreError.clipNotFound(a.id)) { try store.representations(for: a.id) }
    }

    @Test("Clears unpinned clips and keeps pins")
    func clearsUnpinned() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore(HistoryLimits(inlineThreshold: 64))
        let pinnedImage = try store.record(imageDraft(byteCount: 500, seed: 1), at: .at(1))
        try store.record(imageDraft(byteCount: 500, seed: 2), at: .at(2))
        try store.record(textDraft("text"), at: .at(3))
        try store.pin(pinnedImage.id)
        #expect(try blobFiles().count == 2)

        try store.clearUnpinned()
        #expect(store.recent.isEmpty)
        #expect(store.pinned.map(\.id) == [pinnedImage.id])
        #expect(try blobFiles().count == 1)

        let reopened = try makeStore()
        #expect(reopened.pinned.map(\.id) == [pinnedImage.id])
        #expect(reopened.recent.isEmpty)
    }

    @Test("Clears everything, pins included")
    func clearsAll() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore(HistoryLimits(inlineThreshold: 64))
        let image = try store.record(imageDraft(byteCount: 500), at: .at(1))
        try store.record(textDraft("text"), at: .at(2))
        try store.pin(image.id)

        try store.clearAll()
        #expect(store.pinned.isEmpty)
        #expect(store.recent.isEmpty)
        #expect(try blobFiles().isEmpty)
        #expect(try makeStore().recent.isEmpty)
    }

    // MARK: Pruning

    @Test("Prunes the oldest unpinned clips beyond the limit and never pins")
    func prunesBeyondLimit() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore(HistoryLimits(historyLimit: 3))
        let oldest = try store.record(textDraft("0"), at: .at(0))
        try store.pin(oldest.id)
        for index in 1...5 {
            try store.record(textDraft("\(index)"), at: .at(Double(index)))
        }
        #expect(store.recent.map(\.title) == ["5", "4", "3"])
        #expect(store.pinned.map(\.title) == ["0"])

        try store.setHistoryLimit(1)
        #expect(store.historyLimit == 1)
        #expect(store.recent.map(\.title) == ["5"])
        #expect(store.pinned.map(\.title) == ["0"])

        let reopened = try makeStore(HistoryLimits(historyLimit: 3))
        #expect(reopened.recent.map(\.title) == ["5"])
        #expect(reopened.pinned.map(\.title) == ["0"])
    }

    @Test("Prunes at open when the limit was lowered")
    func prunesAtOpen() throws {
        defer { removeTemporaryDirectory(directory) }
        do {
            let store = try makeStore()
            for index in 1...4 {
                try store.record(textDraft("\(index)"), at: .at(Double(index)))
            }
        }
        let store = try makeStore(HistoryLimits(historyLimit: 2))
        #expect(store.recent.map(\.title) == ["4", "3"])
    }

    @Test("Never prunes the clip being recorded, even when backdated")
    func keepsTheRecordedClip() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore(HistoryLimits(historyLimit: 2))
        try store.record(textDraft("new"), at: .at(10))
        try store.record(textDraft("newer"), at: .at(11))
        let backdated = try store.record(textDraft("backdated"), at: .at(1))
        #expect(store.recent.map(\.title) == ["newer", "backdated"])
        #expect(store.clip(withID: backdated.id) != nil)
    }

    // MARK: Blobs

    @Test("Keeps small payloads inline and large ones in blob files")
    func storesLargePayloadsAsBlobs() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore(HistoryLimits(inlineThreshold: 100))
        let text = try store.record(textDraft("small"), at: .at(1))
        #expect(try blobFiles().isEmpty)

        let draft = try imageDraft(byteCount: 1000)
        let image = try store.record(draft, at: .at(2))
        let png = try #require(draft.items.first?.data(for: .png))
        #expect(try blobFiles() == [SHA256.hexDigest(of: png)])
        #expect(try store.representations(for: image.id) == draft.items)
        #expect(try store.representations(for: text.id) == [item((.string, "small"))])
        #expect(image.byteSize == 1000)
    }

    @Test("Deletes blob files once nothing uses them")
    func cleansUpBlobs() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore(HistoryLimits(inlineThreshold: 64))
        let shared = pngData(width: 5, height: 5, byteCount: 400)
        // Two text clips that carry the same large picture share one blob.
        let one = try store.record(try #require(ClipBuilder().build(from: PasteboardSnapshot(items: [PasteboardItem([
            ClipRepresentation(.string, string: "one"), ClipRepresentation(.png, shared),
        ])]))), at: .at(1))
        try store.record(try #require(ClipBuilder().build(from: PasteboardSnapshot(items: [PasteboardItem([
            ClipRepresentation(.string, string: "two"), ClipRepresentation(.png, shared),
        ])]))), at: .at(2))
        #expect(try blobFiles().count == 1)

        try store.delete(one.id)
        #expect(try blobFiles().count == 1)

        // Re-copying "two" with a different picture replaces the blob.
        let replacement = pngData(width: 5, height: 5, byteCount: 400, seed: 9)
        try store.record(try #require(ClipBuilder().build(from: PasteboardSnapshot(items: [PasteboardItem([
            ClipRepresentation(.string, string: "two"), ClipRepresentation(.png, replacement),
        ])]))), at: .at(3))
        #expect(try blobFiles() == [SHA256.hexDigest(of: replacement)])
    }

    @Test("Removes orphaned blob files when opened")
    func cleansUpOrphansAtOpen() throws {
        defer { removeTemporaryDirectory(directory) }
        let kept: String
        do {
            let store = try makeStore(HistoryLimits(inlineThreshold: 64))
            let image = try store.record(try imageDraft(byteCount: 500), at: .at(1))
            kept = try #require(try blobFiles().first)
            _ = image
        }
        let blobs = directory.appendingPathComponent(HistoryStore.blobDirectoryName)
        let orphan = String(repeating: "b", count: 64)
        try Data("orphan".utf8).write(to: blobs.appendingPathComponent(orphan))
        try Data("partial".utf8).write(to: blobs.appendingPathComponent(".tmp-crash"))

        _ = try makeStore(HistoryLimits(inlineThreshold: 64))
        #expect(try FileManager.default.contentsOfDirectory(atPath: blobs.path) == [kept])
    }

    @Test("Reports a missing blob file")
    func reportsMissingBlob() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore(HistoryLimits(inlineThreshold: 64))
        let image = try store.record(try imageDraft(byteCount: 500), at: .at(1))
        let hash = try #require(try blobFiles().first)
        try FileManager.default.removeItem(
            at: directory.appendingPathComponent(HistoryStore.blobDirectoryName).appendingPathComponent(hash)
        )
        #expect(throws: HistoryStoreError.missingBlob(hash: hash)) { try store.representations(for: image.id) }
    }

    // MARK: Persistence

    @Test("Survives reopening")
    func persistsAcrossLaunches() throws {
        defer { removeTemporaryDirectory(directory) }
        let pinnedBefore: [Clip]
        let recentBefore: [Clip]
        let image: Clip
        do {
            let store = try makeStore(HistoryLimits(inlineThreshold: 64))
            let a = try store.record(textDraft("alpha", source: "com.apple.Safari"), at: .at(1.25))
            try store.record(textDraft("https://kept.app/docs"), at: .at(2.5))
            try store.record(textDraft("#FF6A00"), at: .at(3))
            image = try store.record(try imageDraft(byteCount: 300), at: .at(4))
            let b = try store.record(textDraft("beta"), at: .at(5))
            try store.record(textDraft("alpha"), at: .at(6))
            try store.pin(b.id)
            try store.pin(a.id)
            try store.movePin(a.id, toIndex: 0)
            pinnedBefore = store.pinned
            recentBefore = store.recent
        }

        let reopened = try makeStore(HistoryLimits(inlineThreshold: 64))
        #expect(reopened.pinned == pinnedBefore)
        #expect(reopened.recent == recentBefore)
        #expect(reopened.pinned.map(\.title) == ["alpha", "beta"])
        #expect(reopened.pinned[0].copyCount == 2)
        #expect(reopened.recent.map(\.kind) == [.image, .color, .link])
        #expect(reopened.recent.first?.metadata.imagePixelSize == PixelSize(width: 10, height: 10))
        #expect(try reopened.representations(for: image.id).first?.data(for: .png)?.count == 300)
    }

    @Test("Round-trips a multi-item pasteboard in order")
    func roundTripsMultipleItems() throws {
        defer { removeTemporaryDirectory(directory) }
        let large = Data(repeating: 0xAB, count: 200)
        let items = [
            PasteboardItem([ClipRepresentation(.fileURL, string: "file:///a.png"), ClipRepresentation(.string, string: "a.png"),
                            ClipRepresentation(.tiff, large)]),
            PasteboardItem([ClipRepresentation(.fileURL, string: "file:///b.txt"), ClipRepresentation(.string, string: "b.txt")]),
            PasteboardItem([ClipRepresentation(.fileURL, string: "file:///c"), ClipRepresentation(.string, string: "")]),
        ]
        let draft = try #require(ClipBuilder().build(from: PasteboardSnapshot(items: items, sourceBundleID: "com.apple.finder")))
        #expect(draft.items == items)

        let id: UUID
        do {
            let store = try makeStore(HistoryLimits(inlineThreshold: 64))
            id = try store.record(draft).id
            #expect(try store.representations(for: id) == items)
        }
        #expect(try makeStore(HistoryLimits(inlineThreshold: 64)).representations(for: id) == items)
    }

    @Test("Refuses a database written by a newer schema")
    func refusesNewerSchema() throws {
        defer { removeTemporaryDirectory(directory) }
        do { _ = try makeStore() }
        do {
            let database = try SQLiteDatabase(.file(path: directory.appendingPathComponent(HistoryStore.databaseFileName).path))
            try database.setUserVersion(HistorySchema.currentVersion + 1)
        }
        #expect(throws: HistoryStoreError.newerSchema(version: HistorySchema.currentVersion + 1)) {
            try makeStore()
        }
    }

    @Test("Keeps its folder private")
    func usesPrivateFolder() throws {
        defer { removeTemporaryDirectory(directory) }
        let folder = directory.appendingPathComponent("Kept")
        _ = try HistoryStore(directory: folder)
        let attributes = try FileManager.default.attributesOfItem(atPath: folder.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }
}
