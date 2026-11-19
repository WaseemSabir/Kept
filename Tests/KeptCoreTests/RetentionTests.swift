import Foundation
import Testing
@testable import KeptCore

@MainActor
@Suite("Forgetting old clips")
struct RetentionTests {
    let directory: URL

    init() throws {
        directory = try makeTemporaryDirectory()
    }

    private func makeStore() throws -> HistoryStore {
        try HistoryStore(directory: directory, limits: HistoryLimits(inlineThreshold: 64))
    }

    private func blobFiles() throws -> Set<String> {
        let blobs = directory.appendingPathComponent(HistoryStore.blobDirectoryName)
        return Set(try FileManager.default.contentsOfDirectory(atPath: blobs.path).filter { !$0.hasPrefix(".") })
    }

    private func imageDraft(seed: UInt8) throws -> ClipDraft {
        let png = pngData(width: 6, height: 6, byteCount: 300, seed: seed)
        return try #require(ClipBuilder().build(from: PasteboardSnapshot(items: [PasteboardItem([ClipRepresentation(.png, png)])])))
    }

    @Test("Periods turn into cutoffs; never has none")
    func cutoffs() {
        let now = Date.at(1_000_000)
        #expect(RetentionPeriod.never.cutoff(before: now) == nil)
        #expect(RetentionPeriod.day.cutoff(before: now) == now.addingTimeInterval(-86_400))
        #expect(RetentionPeriod.week.cutoff(before: now) == now.addingTimeInterval(-7 * 86_400))
        #expect(RetentionPeriod.month.cutoff(before: now) == now.addingTimeInterval(-30 * 86_400))
        #expect(RetentionPeriod.allCases == [.never, .day, .week, .month])
    }

    @Test("Forgets unpinned clips last copied before the cutoff; pins stay however old")
    func forgetsOldUnpinnedClips() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let oldPin = try store.record(textDraft("old pin"), at: .at(1))
        try store.pin(oldPin.id)
        try store.record(textDraft("old"), at: .at(2))
        try store.record(textDraft("at the cutoff"), at: .at(10))
        let pasted = try store.record(textDraft("old but pasted lately"), at: .at(3))
        try store.markUsed(pasted.id, at: .at(20))
        try store.record(textDraft("new"), at: .at(30))
        let generation = store.clearGeneration

        let forgotten = try store.forgetUnpinned(olderThan: .at(10))
        #expect(forgotten == 1)
        #expect(store.recent.map(\.title) == ["new", "old but pasted lately", "at the cutoff"])
        #expect(store.pinned.map(\.title) == ["old pin"])
        #expect(store.clearGeneration == generation)
        #expect(try store.forgetUnpinned(olderThan: .at(10)) == 0)
        #expect(!store.wasDeleted(textDraft("old").contentHash, after: .at(0)), "copying it again records it")

        let reopened = try makeStore()
        #expect(reopened.recent.map(\.title) == ["new", "old but pasted lately", "at the cutoff"])
        #expect(reopened.pinned.map(\.title) == ["old pin"])
    }

    @Test("Deletes forgotten clips' blob files in the background, keeping shared ones")
    func removesBlobs() throws {
        defer { removeTemporaryDirectory(directory) }
        let store = try makeStore()
        let old = try store.record(try imageDraft(seed: 1), at: .at(1))
        let pinned = try store.record(try imageDraft(seed: 2), at: .at(2))
        try store.pin(pinned.id)
        // Two clips sharing one picture: the newer one keeps it.
        let shared = pngData(width: 5, height: 5, byteCount: 400, seed: 3)
        func textWithPicture(_ text: String) throws -> ClipDraft {
            try #require(ClipBuilder().build(from: PasteboardSnapshot(items: [PasteboardItem([
                ClipRepresentation(.string, string: text), ClipRepresentation(.png, shared),
            ])])))
        }
        try store.record(try textWithPicture("old caption"), at: .at(3))
        try store.record(try textWithPicture("new caption"), at: .at(30))
        let before = try blobFiles()
        #expect(before.count == 3)

        #expect(try store.forgetUnpinned(olderThan: .at(10)) == 2)
        store.waitForBackgroundRemovals()
        #expect(try blobFiles() == before.subtracting([SHA256.hexDigest(of: pngData(width: 6, height: 6, byteCount: 300, seed: 1))]))
        #expect(store.clip(withID: old.id) == nil)
        #expect(try store.representations(for: pinned.id).count == 1)
        #expect(store.recent.map(\.title) == ["new caption"])
        #expect(try store.representations(for: store.recent[0].id).first?.data(for: .png) == shared)
    }

    @Test("A blob reserved again before its background removal keeps its file")
    func reservationCancelsRemoval() throws {
        let reservations = BlobReservations()
        let hash = String(repeating: "a", count: 64)
        reservations.markForRemoval([hash])
        #expect(reservations.isPendingRemoval(hash))
        let reservation = reservations.reserve([hash])
        #expect(!reservations.isPendingRemoval(hash))
        reservation.release()
        var ran = false
        #expect(!reservations.removeIfStillPending(hash) { ran = true })
        #expect(!ran)

        // Reserved when marked: never marked at all.
        let held = reservations.reserve([hash])
        reservations.markForRemoval([hash])
        #expect(!reservations.isPendingRemoval(hash))
        held.release()

        reservations.markForRemoval([hash])
        #expect(reservations.removeIfStillPending(hash) { ran = true })
        #expect(ran)
        #expect(!reservations.isPendingRemoval(hash))
    }

    @Test("Background removal deletes unreserved files and skips reserved ones")
    func backgroundRemoval() throws {
        defer { removeTemporaryDirectory(directory) }
        let blobs = try BlobStore(directory: directory.appendingPathComponent("blobs"))
        let gone = try blobs.write(Data("gone".utf8))
        let kept = try blobs.write(Data("kept".utf8))
        let reservation = blobs.reservations.reserve([kept])
        blobs.removeInBackground([gone, kept, "not-a-hash"])
        blobs.waitForBackgroundRemovals()
        #expect(!blobs.contains(gone))
        #expect(blobs.contains(kept))
        reservation.release()
    }
}
