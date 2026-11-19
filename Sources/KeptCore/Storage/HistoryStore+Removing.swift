import Foundation

/// Deleting, clearing, forgetting old clips and pruning past the limit.
@MainActor
extension HistoryStore {
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

    /// Remembers that `contentHash` was deleted at `date`, for
    /// `wasDeleted(_:after:)`; the oldest of more than
    /// `maxRecentDeletions` are forgotten.
    func noteDeletion(of contentHash: String, at date: Date) {
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

    /// Deletes the oldest unpinned clips beyond the limit, never `keptID`.
    func prune(keeping keptID: UUID? = nil) throws {
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
}
