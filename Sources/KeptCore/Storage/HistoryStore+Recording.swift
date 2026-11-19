import Foundation

/// Recording captures and marking clips used.
@MainActor
extension HistoryStore {
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
        try record(try stage(draft), at: date)
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
            let existing = self.clip(withContentHash: draft.contentHash)
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
            try transaction { try write(clip, representations: representations) }
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

    /// Writes `draft`'s blob files and reserves them, here on the main
    /// actor (`ClipStager.stage(_:)`). If that fails partway, the files
    /// written so far are discarded before the error is thrown.
    func stage(_ draft: ClipDraft) throws(HistoryStoreError) -> StagedClip {
        do throws(ClipStager.Failure) {
            return try stager.stage(draft)
        } catch {
            discard(error.written)
            throw error.error
        }
    }
}
