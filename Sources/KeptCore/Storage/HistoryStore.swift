import Foundation
import Observation

/// The clipboard history: SQLite for clips and small payloads, a blob store
/// for large ones, and every clip's summary kept in memory so the panel
/// opens instantly.
///
/// Invariants: `pinned[i].pinOrder == i`; `recent` holds only unpinned clips,
/// most recently copied first, and never more than `historyLimit` after a
/// `record(_:at:)`. The lists change only together with the database, in a
/// transaction, through this file and its extensions:
///
/// - `HistoryStore+Recording.swift`: recording captures, marking clips used
/// - `HistoryStore+Editing.swift`: renaming and editing a clip's text
/// - `HistoryStore+Pins.swift`: pinning, unpinning and reordering pins
/// - `HistoryStore+Removing.swift`: deleting, clearing, forgetting, pruning
/// - `HistoryStore+Rows.swift`: writing rows and representations, blob files
@MainActor
@Observable
public final class HistoryStore {
    /// Pinned clips, in the order the user arranged them.
    public internal(set) var pinned: [Clip] = []
    /// Unpinned clips, most recently copied first.
    public internal(set) var recent: [Clip] = []
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
    @ObservationIgnored public internal(set) var clearGeneration = 0
    /// When content was last deleted with `delete(_:at:)`, by content hash,
    /// for `wasDeleted(_:after:)`. At most `maxRecentDeletions`; the
    /// oldest go first.
    @ObservationIgnored var recentDeletions: [String: Date] = [:]
    static let maxRecentDeletions = 64

    /// Writes large payloads to blob files off the main actor before
    /// `record(_:at:)` (see `ClipStager`).
    public nonisolated let stager: ClipStager
    /// The folder holding the database and the `blobs` folder.
    public let directory: URL
    let inlineThreshold: Int
    let database: SQLiteDatabase
    let blobs: BlobStore
    let encoder: JSONEncoder
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

    /// Changes how many unpinned clips are kept (at least one) and prunes
    /// the oldest beyond it.
    public func setHistoryLimit(_ limit: Int) throws(HistoryStoreError) {
        historyLimit = max(1, limit)
        try mapErrors { try prune() }
    }

    // MARK: Reading

    public func clip(withID id: UUID) -> Clip? {
        pinned.first { $0.id == id } ?? recent.first { $0.id == id }
    }

    /// The clip holding this content (`Clip.contentHash`), if any.
    public func clip(withContentHash contentHash: String) -> Clip? {
        pinned.first { $0.contentHash == contentHash } ?? recent.first { $0.contentHash == contentHash }
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

    // MARK: Loading

    /// The columns of a clip row, in the order `clip(from:)` reads them.
    static let clipColumns = """
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

    // MARK: In-memory lists

    /// Puts `clip` where it belongs in `pinned` or `recent`, replacing any
    /// older copy of it.
    func place(_ clip: Clip) {
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
    func update(_ clip: Clip) {
        if let index = pinned.firstIndex(where: { $0.id == clip.id }), pinned[index].pinOrder == clip.pinOrder {
            pinned[index] = clip
        } else if let index = recent.firstIndex(where: { $0.id == clip.id }),
                  !clip.isPinned, recent[index].lastCopiedAt == clip.lastCopiedAt {
            recent[index] = clip
        } else {
            place(clip)
        }
    }

    // MARK: Plumbing

    /// Runs `body` in a transaction: commits when it returns, rolls back when it throws.
    func transaction(_ body: () throws -> Void) throws {
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

    /// Runs `body`, reporting every failure as a `HistoryStoreError`.
    func mapErrors<T>(_ body: () throws -> T) throws(HistoryStoreError) -> T {
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
}
