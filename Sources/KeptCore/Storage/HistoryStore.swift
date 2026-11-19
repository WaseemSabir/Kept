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
    /// source are refreshed. Pins stay pinned. Prunes past the limit.
    ///
    /// Writes large payloads to blob files here, on the main actor; capture
    /// stages them off it first and records the `StagedClip` instead.
    @discardableResult
    public func record(_ draft: ClipDraft, at date: Date = Date()) throws(HistoryStoreError) -> Clip {
        try record(stager.stage(draft), at: date)
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
            replacedBlobs.formUnion(try blobHashes(
                query: """
                    SELECT r.blob_hash FROM representations r JOIN clips c ON c.id = r.clip_id
                    WHERE c.content_hash = ? AND c.id <> ? AND r.blob_hash IS NOT NULL
                    """,
                .text(clip.contentHash), .text(clip.id.uuidString)
            ))
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

    public func delete(_ id: UUID) throws(HistoryStoreError) {
        try mapErrors {
            guard clip(withID: id) != nil else { throw HistoryStoreError.clipNotFound(id) }
            try deleteClips([id])
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

    /// Deletes the oldest unpinned clips beyond the limit, never `keptID`.
    private func prune(keeping keptID: UUID? = nil) throws {
        let excess = recent.count - historyLimit
        guard excess > 0 else { return }
        let victims = recent.reversed().lazy.filter { $0.id != keptID }.prefix(excess).map(\.id)
        try deleteClips(Set(victims))
    }

    private func deleteClips(_ ids: Set<UUID>) throws {
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
        try? removeBlobsIfUnreferenced(candidates)
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
        first_copied_at, last_copied_at, copy_count, pin_order, byte_size, metadata
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
            INSERT INTO clips (\(Self.clipColumns)) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET
                kind = excluded.kind, title = excluded.title, search_text = excluded.search_text,
                content_hash = excluded.content_hash, source_bundle_id = excluded.source_bundle_id,
                first_copied_at = excluded.first_copied_at, last_copied_at = excluded.last_copied_at,
                copy_count = excluded.copy_count, pin_order = excluded.pin_order,
                byte_size = excluded.byte_size, metadata = excluded.metadata
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
            .text(metadata)
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

    private func referencedBlobHashes() throws -> Set<String> {
        try blobHashes(query: "SELECT DISTINCT blob_hash FROM representations WHERE blob_hash IS NOT NULL")
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
