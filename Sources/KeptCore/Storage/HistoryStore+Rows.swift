import Foundation

/// Writing clip rows and their representations, and the blob files those
/// reference. Every write here runs inside a caller's `transaction`.
@MainActor
extension HistoryStore {
    /// One row of the `representations` table, ready to insert.
    struct RepresentationRow {
        var itemIndex: Int
        var position: Int
        var type: PasteboardType
        /// Inline bytes, or `nil` when the bytes are in the blob store.
        var data: Data?
        var blobHash: String?
        var size: Int
    }

    /// Writes `clip` with `representations` in place of the ones it had,
    /// deleting any other row with the same content (a clip it merges
    /// with, or a row that couldn't be loaded).
    func write(_ clip: Clip, representations: [RepresentationRow]) throws {
        try database.run(
            "DELETE FROM clips WHERE content_hash = ? AND id <> ?",
            .text(clip.contentHash), .text(clip.id.uuidString)
        )
        try upsert(clip)
        try database.run("DELETE FROM representations WHERE clip_id = ?", .text(clip.id.uuidString))
        try insert(representations, for: clip.id)
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

    // MARK: Representations

    /// Describes every row to insert, writing large payloads to the blob
    /// store unless they're among the `staged` blobs and their files exist.
    /// Hashes `ClipBuilder` or the stager already worked out are reused.
    func storeRepresentations(of items: [PasteboardItem], staged: Set<String>) throws -> [RepresentationRow] {
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

    // MARK: Blob files

    /// The blob hashes the clips with `ids` reference.
    func blobHashes(of ids: some Sequence<UUID>) throws -> Set<String> {
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

    /// The blob hashes in the first column of `query`'s rows.
    func blobHashes(query: String, _ bindings: SQLiteValue...) throws -> Set<String> {
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
    func blobHashesOfOtherClips(withContentHash contentHash: String, than id: UUID) throws -> Set<String> {
        try blobHashes(
            query: """
                SELECT r.blob_hash FROM representations r JOIN clips c ON c.id = r.clip_id
                WHERE c.content_hash = ? AND c.id <> ? AND r.blob_hash IS NOT NULL
                """,
            .text(contentHash), .text(id.uuidString)
        )
    }

    /// Every blob hash a representation references.
    func referencedBlobHashes() throws -> Set<String> {
        try blobHashes(query: "SELECT DISTINCT blob_hash FROM representations WHERE blob_hash IS NOT NULL")
    }

    /// The hashes among `hashes` that no representation uses.
    func unreferencedBlobs(among hashes: Set<String>) throws -> Set<String> {
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
    func removeBlobsIfUnreferenced(_ hashes: Set<String>) throws {
        for hash in try unreferencedBlobs(among: hashes) {
            try blobs.remove(hash)
        }
    }
}
