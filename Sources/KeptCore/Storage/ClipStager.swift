import Foundation

/// Writes a draft's large payloads to blob files before the history
/// records it, so the main actor never writes (and flushes) megabytes.
///
/// Capture gets one from `HistoryStore.stager` and calls `stage(_:)` in
/// its detached build task; `HistoryStore.record(_:at:)` then only writes
/// database rows. It's `Sendable` and touches no database.
public struct ClipStager: Sendable {
    let blobs: BlobStore
    /// Payloads larger than this go to blob files (the store's threshold).
    let inlineThreshold: Int

    /// `draft` with every payload over the inline threshold written to its
    /// blob file (flushed to disk) and reserved, so no deletion removes the
    /// file before `HistoryStore.record(_:at:)` commits the clip or
    /// `HistoryStore.discard(_:)` lets it go. Reuses the hashes `ClipBuilder`
    /// worked out. Runs anywhere.
    public func stage(_ draft: ClipDraft) throws(HistoryStoreError) -> StagedClip {
        var draft = draft
        var hashes = Set<String>()
        for itemIndex in draft.items.indices {
            for index in draft.items[itemIndex].representations.indices {
                let representation = draft.items[itemIndex].representations[index]
                guard representation.data.count > inlineThreshold else { continue }
                let hash = representation.hexDigest
                draft.items[itemIndex].representations[index].sha256 = hash
                hashes.insert(hash)
            }
        }

        // Reserved before any file is checked or written, so a deletion
        // running meanwhile either finishes first or leaves the file alone.
        let reservation = blobs.reservations.reserve(hashes)
        var written = Set<String>()
        for item in draft.items {
            for representation in item.representations where representation.data.count > inlineThreshold {
                guard let hash = representation.sha256, written.insert(hash).inserted else { continue }
                try blobs.write(representation.data, hash: hash)
            }
        }
        return StagedClip(draft: draft, blobHashes: hashes, reservation: reservation)
    }
}
