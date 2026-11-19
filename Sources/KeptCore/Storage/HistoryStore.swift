import Foundation
import Observation

/// The clipboard history: SQLite for clips and small payloads, a blob store
/// for large ones, and every clip's summary kept in memory so the panel
/// opens instantly.
///
/// Invariants: `pinned[i].pinOrder == i`; `recent` holds only unpinned clips,
/// most recently copied first, and never more than `historyLimit` after a
/// `record(_:at:)`.
@MainActor
@Observable
public final class HistoryStore {
    /// Pinned clips, in the order the user arranged them.
    public private(set) var pinned: [Clip] = []
    /// Unpinned clips, most recently copied first.
    public private(set) var recent: [Clip] = []
    /// How many unpinned clips are kept before the oldest are pruned.
    public private(set) var historyLimit: Int
    /// Rows that couldn't be read when the store opened (an unknown kind,
    /// say from a newer Kept, or an invalid ID). They are left untouched in
    /// the database: never shown, pruned or swept, but replaced when the
    /// same content is copied again and removed by `clearUnpinned()` or
    /// `clearAll()`.
    public private(set) var skippedRecordCount = 0
    /// Problems found while opening that didn't stop the store from opening:
    /// skipped or partly read rows, and a failed renumbering, prune or blob
    /// sweep (all retried at the next launch). At most `maxOpenWarnings`.
    public private(set) var openWarnings: [HistoryStoreError] = []
    /// Goes up each time `clearUnpinned()` or `clearAll()` runs, so capture
    /// can drop a clip whose copy was seen before the history was cleared
    /// but whose build finished after.
    @ObservationIgnored public private(set) var clearGeneration = 0
    /// When content was last deleted with `delete(_:at:)`, by content hash,
    /// for `wasDeleted(_:after:)`. At most `maxRecentDeletions`; the
    /// oldest go first.
    @ObservationIgnored private var recentDeletions: [String: Date] = [:]
    static let maxRecentDeletions = 64

    /// Writes large payloads to blob files off the main actor before
    /// `record(_:at:)` (see `ClipStager`).
    public nonisolated let stager: ClipStager
    /// The folder holding the database and the `blobs` folder.
    public let directory: URL
    private let inlineThreshold: Int
    private let database: SQLiteDatabase
    private let blobs: BlobStore
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    static let databaseFileName = "History.sqlite"
    static let blobDirectoryName = "blobs"
    static let maxOpenWarnings = 20
    /// How long a write waits for another connection's lock before failing.
    static let busyTimeoutMilliseconds = 5000

    /// Opens (creating if needed) the history in `directory`, then prunes
    /// to the limit and deletes blob files nothing references.
    ///
    /// Throws only when the history can't be used at all (the folder or
    /// database can't be opened, or a newer Kept's schema). Unreadable rows
    /// are skipped (`skippedRecordCount`), and housekeeping that fails is
    /// reported in `openWarnings` instead.
    public init(directory: URL, limits: HistoryLimits = HistoryLimits()) throws(HistoryStoreError) {
        self.directory = directory
        historyLimit = max(1, limits.historyLimit)
        inlineThreshold = max(0, limits.inlineThreshold)
        encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        try BlobStore.createPrivateDirectory(at: directory)
        let path = directory.appendingPathComponent(Self.databaseFileName).path
        // SQLite gives the -wal and -shm files the database file's permissions.
        if !FileManager.default.fileExists(atPath: path) {
            _ = FileManager.default.createFile(atPath: path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        for file in [path, path + "-wal", path + "-shm"] {
            BlobStore.makePrivate(file, permissions: 0o600)
        }
        do throws(SQLiteError) {
            database = try SQLiteDatabase(.file(path: path))
            try database.execute("""
                PRAGMA busy_timeout = \(Self.busyTimeoutMilliseconds);
                PRAGMA journal_mode = WAL;
                PRAGMA synchronous = NORMAL;
                PRAGMA foreign_keys = ON;
                PRAGMA secure_delete = ON;
                """)
        } catch {
            throw .database(error)
        }
        try HistorySchema.migrate(database)
        blobs = try BlobStore(directory: directory.appendingPathComponent(Self.blobDirectoryName, isDirectory: true))
        stager = ClipStager(blobs: blobs, inlineThreshold: inlineThreshold)

        try mapErrors {
            pinned = try fetchClips("pin_order IS NOT NULL ORDER BY pin_order, rowid")
            recent = try fetchClips("pin_order IS NULL ORDER BY last_copied_at DESC, rowid DESC")
        }
        if pinned.enumerated().contains(where: { $0.element.pinOrder != $0.offset }) {
            var renumbered = pinned
            bestEffort { try transaction { try writePinOrder(&renumbered) } }
            // Keep the in-memory invariant even if the database kept the old
            // numbers; they sort the same, and the next launch retries.
            for index in renumbered.indices { renumbered[index].pinOrder = index }
            pinned = renumbered
        }
        bestEffort { try prune() }
        // Only sweep when the references are known; an error leaves every file.
        bestEffort { try blobs.removeAll(except: referencedBlobHashes()) }
    }

    // MARK: Reading

    public func clip(withID id: UUID) -> Clip? {
        pinned.first { $0.id == id } ?? recent.first { $0.id == id }
    }

    /// The clip's pasteboard items with every representation's bytes, in the
    /// order they were captured.
    public func representations(for id: UUID) throws(HistoryStoreError) -> [PasteboardItem] {
        try storedRepresentations(for: id).load()
    }

    /// The clip's representations of `types` only, item by item in the
    /// order captured; items with none of them are left out. Reads no blob
    /// file of another type, so showing a text clip's text never loads the
    /// multi-megabyte image an app put next to it.
    public func representations(
        for id: UUID,
        types: Set<PasteboardType>
    ) throws(HistoryStoreError) -> [PasteboardItem] {
        try storedRepresentations(for: id, types: types).load()
    }

    /// Finds the clip's representations (of `types`, or all of them) without
    /// reading blob files, for `StoredRepresentations.load()` to read later,
    /// off the main actor when they're big.
    public func storedRepresentations(
        for id: UUID,
        types: Set<PasteboardType>? = nil
    ) throws(HistoryStoreError) -> StoredRepresentations {
        try mapErrors {
            guard clip(withID: id) != nil else { throw HistoryStoreError.clipNotFound(id) }
            let typeNames = types.map { $0.map(\.rawValue).sorted() } ?? []
            if types != nil, typeNames.isEmpty { return StoredRepresentations(entries: [], blobs: blobs) }

            var sql = "SELECT item_index, type, data, blob_hash, size FROM representations WHERE clip_id = ?"
            if !typeNames.isEmpty {
                sql += " AND type IN (" + Array(repeating: "?", count: typeNames.count).joined(separator: ", ") + ")"
            }
            sql += " ORDER BY item_index, position"
            let statement = try database.prepare(sql)
            try statement.bind(id.uuidString, at: 1)
            for (offset, name) in typeNames.enumerated() {
                try statement.bind(name, at: offset + 2)
            }

            var entries: [StoredRepresentations.Entry] = []
            while try statement.step() {
                guard let type = statement.string(at: 1) else {
                    throw HistoryStoreError.corruptRecord("A representation of \(id) has no type.")
                }
                let inline = statement.data(at: 2)
                let hash = inline == nil ? statement.string(at: 3) : nil
                guard inline != nil || hash != nil else {
                    throw HistoryStoreError.corruptRecord("A representation of \(id) has no data.")
                }
                entries.append(StoredRepresentations.Entry(
                    itemIndex: statement.int(at: 0),
                    type: PasteboardType(type),
                    size: statement.int(at: 4),
                    inlineData: inline,
                    blobHash: hash
                ))
            }
            return StoredRepresentations(entries: entries, blobs: blobs)
        }
    }

    // MARK: Recording

    /// Adds a captured clip, or, when the same content is already kept,
    /// moves that clip to the top: `lastCopiedAt` becomes `date`,
    /// `copyCount` goes up by one, and the representations, kind, title and
    /// source are refreshed. Pins stay pinned and custom titles stay. Prunes
    /// past the limit.
    ///
    /// Writes large payloads to blob files here, on the main actor; capture
    /// stages them off it first and records the `StagedClip` instead.
    @discardableResult
    public func record(_ draft: ClipDraft, at date: Date = Date()) throws(HistoryStoreError) -> Clip {
        let staged: StagedClip
        do throws(ClipStager.Failure) {
            staged = try stager.stage(draft)
        } catch {
            discard(error.written)
            throw error.error
        }
        return try record(staged, at: date)
    }

    /// Records a clip whose blob files `stager` already wrote, as
    /// `record(_:at:)` does for a draft; only database rows are written
    /// here (a blob file that has gone missing meanwhile is written again).
    /// Ends the staging either way: if recording fails, the blob files are
    /// deleted unless another clip uses them.
    @discardableResult
    public func record(_ staged: StagedClip, at date: Date = Date()) throws(HistoryStoreError) -> Clip {
        defer { discard(staged) }
        let draft = staged.draft
        return try mapErrors {
            let existing = pinned.first { $0.contentHash == draft.contentHash }
                ?? recent.first { $0.contentHash == draft.contentHash }
            let clip = Clip(
                id: existing?.id ?? UUID(),
                kind: draft.kind,
                title: draft.title,
                customTitle: existing?.customTitle,
                searchText: draft.searchText,
                contentHash: draft.contentHash,
                sourceBundleID: draft.sourceBundleID ?? existing?.sourceBundleID,
                firstCopiedAt: existing?.firstCopiedAt ?? date,
                lastCopiedAt: date,
                copyCount: (existing?.copyCount ?? 0) + 1,
                pinOrder: existing?.pinOrder,
                byteSize: draft.byteSize,
                metadata: draft.metadata
            )

            // Blob files go first (flushed to disk, usually by the stager), so
            // a committed row never points at a missing file.
            let representations = try storeRepresentations(of: draft.items, staged: staged.blobHashes)
            var replacedBlobs = try existing.map { try blobHashes(of: [$0.id]) } ?? []
            // A row with the same content that wasn't loaded (unreadable, or
            // from a newer Kept) gives way to the new copy.
            replacedBlobs.formUnion(try blobHashesOfOtherClips(withContentHash: clip.contentHash, than: clip.id))
            try transaction {
                try database.run(
                    "DELETE FROM clips WHERE content_hash = ? AND id <> ?",
                    .text(clip.contentHash), .text(clip.id.uuidString)
                )
                try upsert(clip)
                try database.run("DELETE FROM representations WHERE clip_id = ?", .text(clip.id.uuidString))
                try insert(representations, for: clip.id)
            }
            place(clip)
            try prune(keeping: clip.id)
            // Committed; a file left behind is swept at the next launch.
            try? removeBlobsIfUnreferenced(replacedBlobs)
            return clip
        }
    }

    /// Lets go of a staged clip that won't be recorded, deleting its blob
    /// files unless a clip (or another staged clip) uses them.
    public func discard(_ staged: StagedClip) {
        staged.reservation.release()
        try? removeBlobsIfUnreferenced(staged.blobHashes)
    }

    /// Moves a clip to the top after it was pasted from Kept.
    public func markUsed(_ id: UUID, at date: Date = Date()) throws(HistoryStoreError) {
        try mapErrors {
            guard var clip = clip(withID: id) else { throw HistoryStoreError.clipNotFound(id) }
            clip.lastCopiedAt = date
            try database.run(
                "UPDATE clips SET last_copied_at = ? WHERE id = ?",
                .real(date.timeIntervalSinceReferenceDate), .text(id.uuidString)
            )
            place(clip)
        }
    }

    // MARK: Renaming and editing

    /// Gives a clip a name that the list shows instead of its text. The
    /// name is sanitized like a title (one line, invisible characters
    /// dropped) and cut to `Clip.maxCustomTitleCharacters`; `nil`, a blank
    /// name, or the clip's own generated title clears it. The clip stays
    /// where it is. Returns the renamed clip.
    @discardableResult
    public func rename(_ id: UUID, to title: String?) throws(HistoryStoreError) -> Clip {
        guard let clip = clip(withID: id) else { throw .clipNotFound(id) }
        var customTitle = Clip.sanitizedCustomTitle(title)
        if customTitle == clip.title { customTitle = nil }
        guard customTitle != clip.customTitle else { return clip }
        let renamed = clip.withCustomTitle(customTitle)
        try mapErrors {
            try database.run(
                "UPDATE clips SET custom_title = ? WHERE id = ?",
                .optional(customTitle), .text(id.uuidString)
            )
        }
        update(renamed)
        return renamed
    }

    /// Replaces a text-like clip's content (text, rich text, a link or a
    /// color) with `text` as plain text: its representations become one
    /// plain string, and its kind (text can become a link or a color, and
    /// back), title, search text, metadata and content hash are worked out
    /// again as for a copy. It keeps its ID, pin, custom title, copy count,
    /// source and dates, so it stays where it is.
    ///
    /// If another clip already holds the new content, the two merge into
    /// the edited one: it takes the other's pin when it has none (its place
    /// among the pins), its custom title when it has none, its copies
    /// (copy counts add up), the earlier first copy and the later last
    /// copy; the other clip is deleted.
    ///
    /// The old content is remembered as deleted at `date`
    /// (`wasDeleted(_:after:)`), so a copy of it seen before the edit and
    /// recorded after can't bring it back as a clip of its own; a copy made
    /// after the edit is recorded as usual. `clearGeneration` doesn't move,
    /// so other captures in flight still land.
    ///
    /// Throws `.notEditable` for images and files, and `.emptyText` when
    /// `text` has nothing visible.
    @discardableResult
    public func editText(_ id: UUID, to text: String, at date: Date = Date()) throws(HistoryStoreError) -> Clip {
        guard let original = clip(withID: id) else { throw .clipNotFound(id) }
        guard original.kind.isTextLike else { throw .notEditable(id) }
        guard let draft = ClipBuilder.draft(forEditedText: text) else { throw .emptyText }
        // Reserved like a capture's, so no deletion, now or in the
        // background, removes a blob file the edit is about to use.
        let staged: StagedClip
        do throws(ClipStager.Failure) {
            staged = try stager.stage(draft)
        } catch {
            discard(error.written)
            throw error.error
        }
        defer { discard(staged) }

        return try mapErrors {
            let duplicate = (pinned + recent).first { $0.contentHash == draft.contentHash && $0.id != id }
            let edited = Clip(
                id: id,
                kind: draft.kind,
                title: draft.title,
                customTitle: original.customTitle ?? duplicate?.customTitle,
                searchText: draft.searchText,
                contentHash: draft.contentHash,
                sourceBundleID: original.sourceBundleID,
                firstCopiedAt: min(original.firstCopiedAt, duplicate?.firstCopiedAt ?? original.firstCopiedAt),
                lastCopiedAt: max(original.lastCopiedAt, duplicate?.lastCopiedAt ?? original.lastCopiedAt),
                copyCount: original.copyCount + (duplicate?.copyCount ?? 0),
                pinOrder: original.pinOrder ?? duplicate?.pinOrder,
                byteSize: draft.byteSize,
                metadata: draft.metadata
            )

            // The pins afterwards: the edited clip in its own place, or in
            // the duplicate's when only that one was pinned.
            var pins = pinned
            if let duplicate, let index = pins.firstIndex(where: { $0.id == duplicate.id }) {
                if original.isPinned {
                    pins.remove(at: index)
                } else {
                    pins[index] = edited
                }
            }
            if let index = pins.firstIndex(where: { $0.id == id }) { pins[index] = edited }

            let representations = try storeRepresentations(of: staged.draft.items, staged: staged.blobHashes)
            var replacedBlobs = try blobHashes(of: [id] + (duplicate.map { [$0.id] } ?? []))
            replacedBlobs.formUnion(try blobHashesOfOtherClips(withContentHash: edited.contentHash, than: id))
            try transaction {
                // The duplicate, and any unreadable row with the same content.
                try database.run(
                    "DELETE FROM clips WHERE content_hash = ? AND id <> ?",
                    .text(edited.contentHash), .text(id.uuidString)
                )
                try upsert(edited)
                try database.run("DELETE FROM representations WHERE clip_id = ?", .text(id.uuidString))
                try insert(representations, for: id)
                try writePinOrder(&pins)
            }

            if let duplicate { recent.removeAll { $0.id == duplicate.id } }
            if pins != pinned { pinned = pins }
            let result = pins.first { $0.id == id } ?? edited
            if result.isPinned {
                recent.removeAll { $0.id == id }
            } else {
                update(result)
            }
            if original.contentHash != result.contentHash {
                noteDeletion(of: original.contentHash, at: date)
            }
            // Committed; a file left behind is swept at the next launch.
            try? removeBlobsIfUnreferenced(replacedBlobs)
            return result
        }
    }

    // MARK: Pins

    /// Pins a clip at the end of the pins. Pinning a pinned clip does nothing.
    public func pin(_ id: UUID) throws(HistoryStoreError) {
        try mapErrors {
            guard var clip = clip(withID: id) else { throw HistoryStoreError.clipNotFound(id) }
            guard !clip.isPinned else { return }
            let order = pinned.count
            clip.pinOrder = order
            try database.run("UPDATE clips SET pin_order = ? WHERE id = ?", .int(order), .text(id.uuidString))
            place(clip)
        }
    }

    /// Returns a pinned clip to the top of the history: its `lastCopiedAt`
    /// becomes `date`, so an old clip isn't pruned by the next copy.
    /// Unpinning an unpinned clip does nothing.
    public func unpin(_ id: UUID, at date: Date = Date()) throws(HistoryStoreError) {
        try mapErrors {
            guard var clip = clip(withID: id) else { throw HistoryStoreError.clipNotFound(id) }
            guard clip.isPinned else { return }
            clip.pinOrder = nil
            clip.lastCopiedAt = date
            var remaining = pinned.filter { $0.id != id }
            try transaction {
                try database.run(
                    "UPDATE clips SET pin_order = NULL, last_copied_at = ? WHERE id = ?",
                    .real(date.timeIntervalSinceReferenceDate), .text(id.uuidString)
                )
                try writePinOrder(&remaining)
            }
            pinned = remaining
            place(clip)
        }
    }

    /// Moves a pinned clip to `index` among the pins (clamped to the valid
    /// range). Does nothing for an unpinned clip.
    public func movePin(_ id: UUID, toIndex index: Int) throws(HistoryStoreError) {
        try mapErrors {
            guard clip(withID: id) != nil else { throw HistoryStoreError.clipNotFound(id) }
            guard let from = pinned.firstIndex(where: { $0.id == id }) else { return }
            var reordered = pinned
            let clip = reordered.remove(at: from)
            reordered.insert(clip, at: min(max(0, index), reordered.count))
            try transaction { try writePinOrder(&reordered) }
            pinned = reordered
        }
    }

    // MARK: Removing

    /// Deletes a clip, and remembers for a while that its content was
    /// deleted at `date` (see `wasDeleted(_:after:)`).
    public func delete(_ id: UUID, at date: Date = Date()) throws(HistoryStoreError) {
        try mapErrors {
            guard let clip = clip(withID: id) else { throw HistoryStoreError.clipNotFound(id) }
            try deleteClips([id])
            noteDeletion(of: clip.contentHash, at: date)
        }
    }

    /// Whether a clip with `contentHash` was deleted (`delete(_:at:)`) after
    /// `date`. Capture asks before recording a copy seen at `date` whose
    /// build finished later, so a deleted clip isn't brought straight back
    /// by a copy made before the user deleted it.
    public func wasDeleted(_ contentHash: String, after date: Date) -> Bool {
        guard let deletedAt = recentDeletions[contentHash] else { return false }
        return deletedAt > date
    }

    private func noteDeletion(of contentHash: String, at date: Date) {
        recentDeletions[contentHash] = max(date, recentDeletions[contentHash] ?? date)
        while recentDeletions.count > Self.maxRecentDeletions,
              let oldest = recentDeletions.min(by: { $0.value < $1.value })?.key {
            recentDeletions[oldest] = nil
        }
    }

    /// Deletes every unpinned clip; pins stay.
    public func clearUnpinned() throws(HistoryStoreError) {
        clearGeneration += 1
        try mapErrors {
            let candidates = try blobHashes(
                query: """
                    SELECT DISTINCT r.blob_hash FROM representations r JOIN clips c ON c.id = r.clip_id
                    WHERE c.pin_order IS NULL AND r.blob_hash IS NOT NULL
                    """
            )
            try database.run("DELETE FROM clips WHERE pin_order IS NULL")
            recent = []
            try removeBlobsIfUnreferenced(candidates)
        }
    }

    /// Deletes everything, pins included. Blob files reserved for clips not
    /// recorded yet stay until those are recorded or discarded.
    public func clearAll() throws(HistoryStoreError) {
        clearGeneration += 1
        try mapErrors {
            try database.run("DELETE FROM clips")
            pinned = []
            recent = []
            try blobs.removeAll(except: [])
        }
    }

    /// Deletes every unpinned clip last copied or pasted before `cutoff`
    /// ("Forget unpinned clips"); pins always stay. Returns how many went.
    ///
    /// The rows go at once; their blob files that nothing else uses are
    /// deleted on a background queue, so forgetting a big history doesn't
    /// hold up the main actor. Forgotten content isn't remembered as
    /// deleted: copying it again records it as usual.
    @discardableResult
    public func forgetUnpinned(olderThan cutoff: Date) throws(HistoryStoreError) -> Int {
        let victims = Set(recent.lazy.filter { $0.lastCopiedAt < cutoff }.map(\.id))
        guard !victims.isEmpty else { return 0 }
        try mapErrors { try deleteClips(victims, removingBlobs: .inBackground) }
        return victims.count
    }

    /// Returns once the blob files of forgotten clips are deleted (for tests).
    func waitForBackgroundRemovals() {
        blobs.waitForBackgroundRemovals()
    }

    /// Changes how many unpinned clips are kept (at least one) and prunes
    /// the oldest beyond it.
    public func setHistoryLimit(_ limit: Int) throws(HistoryStoreError) {
        historyLimit = max(1, limit)
        try mapErrors { try prune() }
    }

    // MARK: In-memory lists

    /// Puts `clip` where it belongs in `pinned` or `recent`, replacing any
    /// older copy of it.
    private func place(_ clip: Clip) {
        var pinned = self.pinned
        var recent = self.recent
        pinned.removeAll { $0.id == clip.id }
        recent.removeAll { $0.id == clip.id }
        if let order = clip.pinOrder {
            pinned.insert(clip, at: min(order, pinned.count))
        } else {
            let index = recent.firstIndex { $0.lastCopiedAt <= clip.lastCopiedAt } ?? recent.endIndex
            recent.insert(clip, at: index)
        }
        if pinned != self.pinned { self.pinned = pinned }
        self.recent = recent
    }

    /// Puts a changed `clip` where its older copy was when it hasn't moved
    /// (same pin, same last copy), so clips copied at the same moment keep
    /// their order; otherwise `place(_:)`.
    private func update(_ clip: Clip) {
        if let index = pinned.firstIndex(where: { $0.id == clip.id }), pinned[index].pinOrder == clip.pinOrder {
            pinned[index] = clip
        } else if let index = recent.firstIndex(where: { $0.id == clip.id }),
                  !clip.isPinned, recent[index].lastCopiedAt == clip.lastCopiedAt {
            recent[index] = clip
        } else {
            place(clip)
        }
    }

    /// Deletes the oldest unpinned clips beyond the limit, never `keptID`.
    private func prune(keeping keptID: UUID? = nil) throws {
        let excess = recent.count - historyLimit
        guard excess > 0 else { return }
        let victims = recent.reversed().lazy.filter { $0.id != keptID }.prefix(excess).map(\.id)
        try deleteClips(Set(victims))
    }

    /// When a deletion deletes the blob files nothing uses any more.
    private enum BlobRemoval {
        /// Right away, on the main actor.
        case now
        /// On a background queue (`BlobStore.removeInBackground(_:)`).
        case inBackground
    }

    private func deleteClips(_ ids: Set<UUID>, removingBlobs removal: BlobRemoval = .now) throws {
        guard !ids.isEmpty else { return }
        let candidates = try blobHashes(of: ids)
        var remainingPins = pinned.filter { !ids.contains($0.id) }
        try transaction {
            let statement = try database.prepare("DELETE FROM clips WHERE id = ?")
            for id in ids {
                try statement.bind(id.uuidString, at: 1)
                try statement.run()
                try statement.reset()
            }
            if remainingPins.count != pinned.count {
                try writePinOrder(&remainingPins)
            }
        }
        if remainingPins.count != pinned.count { pinned = remainingPins }
        recent.removeAll { ids.contains($0.id) }
        // Committed; a file left behind is swept at the next launch.
        switch removal {
        case .now:
            try? removeBlobsIfUnreferenced(candidates)
        case .inBackground:
            if let unreferenced = try? unreferencedBlobs(among: candidates) {
                blobs.removeInBackground(unreferenced)
            }
        }
    }

    /// Renumbers `pins` 0, 1, 2… in the database and in place.
    private func writePinOrder(_ pins: inout [Clip]) throws {
        let statement = try database.prepare("UPDATE clips SET pin_order = ? WHERE id = ?")
        for index in pins.indices where pins[index].pinOrder != index {
            try statement.bind(index, at: 1)
            try statement.bind(pins[index].id.uuidString, at: 2)
            try statement.run()
            try statement.reset()
            pins[index].pinOrder = index
        }
    }

    // MARK: Rows

    private static let clipColumns = """
        id, kind, title, search_text, content_hash, source_bundle_id,
        first_copied_at, last_copied_at, copy_count, pin_order, byte_size, metadata, custom_title
        """

    /// The clips matching `clause` that can be read; the others are counted
    /// in `skippedRecordCount` and noted in `openWarnings`.
    private func fetchClips(_ clause: String) throws -> [Clip] {
        let statement = try database.prepare("SELECT \(Self.clipColumns) FROM clips WHERE \(clause)")
        var clips: [Clip] = []
        while try statement.step() {
            if let clip = clip(from: statement) { clips.append(clip) }
        }
        return clips
    }

    /// The clip a row describes, or `nil` (with a warning) when it can't be
    /// shown: an invalid ID, or a kind this version doesn't know. Metadata
    /// that can't be decoded is dropped rather than the whole clip.
    private func clip(from row: SQLiteStatement) -> Clip? {
        guard let idString = row.string(at: 0), let id = UUID(uuidString: idString) else {
            skippedRecordCount += 1
            warn(.corruptRecord("A clip has an invalid ID; it was skipped."))
            return nil
        }
        guard let kindName = row.string(at: 1), let kind = ClipKind(rawValue: kindName) else {
            skippedRecordCount += 1
            warn(.corruptRecord("Clip \(id) has an unknown kind; it was skipped."))
            return nil
        }
        let metadata: ClipMetadata
        do {
            metadata = try decoder.decode(ClipMetadata.self, from: Data((row.string(at: 11) ?? "{}").utf8))
        } catch {
            warn(.corruptRecord("Clip \(id) has unreadable metadata; it was loaded without it."))
            metadata = ClipMetadata()
        }
        return Clip(
            id: id,
            kind: kind,
            title: row.string(at: 2) ?? "",
            // Sanitized again: the database is a file anything could write.
            customTitle: Clip.sanitizedCustomTitle(row.string(at: 12)),
            searchText: row.string(at: 3) ?? "",
            contentHash: row.string(at: 4) ?? "",
            sourceBundleID: row.string(at: 5),
            firstCopiedAt: Date(timeIntervalSinceReferenceDate: row.double(at: 6)),
            lastCopiedAt: Date(timeIntervalSinceReferenceDate: row.double(at: 7)),
            copyCount: row.int(at: 8),
            pinOrder: row.isNull(at: 9) ? nil : row.int(at: 9),
            byteSize: row.int(at: 10),
            metadata: metadata
        )
    }

    private func upsert(_ clip: Clip) throws {
        let metadata: String
        do {
            metadata = String(decoding: try encoder.encode(clip.metadata), as: UTF8.self)
        } catch {
            throw HistoryStoreError.corruptRecord("Clip \(clip.id) has metadata that can't be saved.")
        }
        try database.run(
            """
            INSERT INTO clips (\(Self.clipColumns)) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET
                kind = excluded.kind, title = excluded.title, search_text = excluded.search_text,
                content_hash = excluded.content_hash, source_bundle_id = excluded.source_bundle_id,
                first_copied_at = excluded.first_copied_at, last_copied_at = excluded.last_copied_at,
                copy_count = excluded.copy_count, pin_order = excluded.pin_order,
                byte_size = excluded.byte_size, metadata = excluded.metadata,
                custom_title = excluded.custom_title
            """,
            .text(clip.id.uuidString),
            .text(clip.kind.rawValue),
            .text(clip.title),
            .text(clip.searchText),
            .text(clip.contentHash),
            .optional(clip.sourceBundleID),
            .real(clip.firstCopiedAt.timeIntervalSinceReferenceDate),
            .real(clip.lastCopiedAt.timeIntervalSinceReferenceDate),
            .int(clip.copyCount),
            .optional(clip.pinOrder),
            .int(clip.byteSize),
            .text(metadata),
            .optional(clip.customTitle)
        )
    }

    // MARK: Representations and blobs

    private struct RepresentationRow {
        var itemIndex: Int
        var position: Int
        var type: PasteboardType
        /// Inline bytes, or `nil` when the bytes are in the blob store.
        var data: Data?
        var blobHash: String?
        var size: Int
    }

    /// Describes every row to insert, writing large payloads to the blob
    /// store unless they're among the `staged` blobs and their files exist.
    /// Hashes `ClipBuilder` or the stager already worked out are reused.
    private func storeRepresentations(of items: [PasteboardItem], staged: Set<String>) throws -> [RepresentationRow] {
        var rows: [RepresentationRow] = []
        for (itemIndex, item) in items.enumerated() {
            for (position, representation) in item.representations.enumerated() {
                let size = representation.data.count
                var blobHash: String?
                if size > inlineThreshold {
                    if let hash = representation.sha256, staged.contains(hash), blobs.contains(hash) {
                        blobHash = hash
                    } else {
                        blobHash = try blobs.write(representation.data, hash: representation.sha256)
                    }
                }
                rows.append(RepresentationRow(
                    itemIndex: itemIndex,
                    position: position,
                    type: representation.type,
                    data: blobHash == nil ? representation.data : nil,
                    blobHash: blobHash,
                    size: size
                ))
            }
        }
        return rows
    }

    private func insert(_ representations: [RepresentationRow], for id: UUID) throws {
        let statement = try database.prepare("""
            INSERT INTO representations (clip_id, item_index, position, type, data, blob_hash, size)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """)
        for representation in representations {
            try statement.bind([
                .text(id.uuidString),
                .int(representation.itemIndex),
                .int(representation.position),
                .text(representation.type.rawValue),
                representation.data.map(SQLiteValue.blob) ?? .null,
                .optional(representation.blobHash),
                .int(representation.size),
            ])
            try statement.run()
            try statement.reset()
        }
    }

    private func blobHashes(of ids: some Sequence<UUID>) throws -> Set<String> {
        let statement = try database.prepare(
            "SELECT blob_hash FROM representations WHERE clip_id = ? AND blob_hash IS NOT NULL"
        )
        var hashes = Set<String>()
        for id in ids {
            try statement.bind(id.uuidString, at: 1)
            while try statement.step() {
                if let hash = statement.string(at: 0) { hashes.insert(hash) }
            }
            try statement.reset()
        }
        return hashes
    }

    private func blobHashes(query: String, _ bindings: SQLiteValue...) throws -> Set<String> {
        let statement = try database.prepare(query)
        try statement.bind(bindings)
        var hashes = Set<String>()
        while try statement.step() {
            if let hash = statement.string(at: 0) { hashes.insert(hash) }
        }
        return hashes
    }

    /// Blob hashes used by clips other than `id` with this content: the
    /// row a clip with new content replaces (unreadable, or from a newer Kept).
    private func blobHashesOfOtherClips(withContentHash contentHash: String, than id: UUID) throws -> Set<String> {
        try blobHashes(
            query: """
                SELECT r.blob_hash FROM representations r JOIN clips c ON c.id = r.clip_id
                WHERE c.content_hash = ? AND c.id <> ? AND r.blob_hash IS NOT NULL
                """,
            .text(contentHash), .text(id.uuidString)
        )
    }

    private func referencedBlobHashes() throws -> Set<String> {
        try blobHashes(query: "SELECT DISTINCT blob_hash FROM representations WHERE blob_hash IS NOT NULL")
    }

    /// The hashes among `hashes` that no representation uses.
    private func unreferencedBlobs(among hashes: Set<String>) throws -> Set<String> {
        guard !hashes.isEmpty else { return [] }
        let statement = try database.prepare("SELECT 1 FROM representations WHERE blob_hash = ? LIMIT 1")
        var unreferenced = Set<String>()
        for hash in hashes {
            try statement.bind(hash, at: 1)
            let isReferenced = try statement.step()
            try statement.reset()
            if !isReferenced { unreferenced.insert(hash) }
        }
        return unreferenced
    }

    /// Deletes the blob files among `hashes` that no representation uses.
    private func removeBlobsIfUnreferenced(_ hashes: Set<String>) throws {
        guard !hashes.isEmpty else { return }
        let statement = try database.prepare("SELECT 1 FROM representations WHERE blob_hash = ? LIMIT 1")
        for hash in hashes {
            try statement.bind(hash, at: 1)
            let isReferenced = try statement.step()
            try statement.reset()
            if !isReferenced { try blobs.remove(hash) }
        }
    }

    // MARK: Plumbing

    /// Runs `body` in a transaction: commits when it returns, rolls back when it throws.
    private func transaction(_ body: () throws -> Void) throws {
        try database.beginTransaction()
        do {
            try body()
            try database.commit()
        } catch {
            // The original error explains the failure better than a failed rollback would.
            try? database.rollback()
            throw error
        }
    }

    /// Runs housekeeping that may fail without making the store unusable,
    /// noting a failure in `openWarnings`.
    private func bestEffort(_ body: () throws -> Void) {
        do throws(HistoryStoreError) {
            try mapErrors(body)
        } catch {
            warn(error)
        }
    }

    private func warn(_ warning: HistoryStoreError) {
        if openWarnings.count < Self.maxOpenWarnings { openWarnings.append(warning) }
    }

    /// Runs `body`, reporting every failure as a `HistoryStoreError`.
    private func mapErrors<T>(_ body: () throws -> T) throws(HistoryStoreError) -> T {
        do {
            return try body()
        } catch let error as HistoryStoreError {
            throw error
        } catch let error as SQLiteError {
            throw .database(error)
        } catch {
            throw .fileSystem(path: directory.path, reason: String(describing: error))
        }
    }
}
