import Dispatch
import Foundation

/// Writes a draft's large payloads to blob files before the history
/// records it, so the main actor never writes (and flushes) megabytes.
///
/// Capture gets one from `HistoryStore.stager` and awaits
/// `stageInBackground(_:)` in its build task; `HistoryStore.record(_:at:)`
/// then only writes database rows. It's `Sendable` and touches no database.
public struct ClipStager: Sendable {
    /// Why staging failed, and what it had written by then.
    public struct Failure: Error, Sendable {
        public let error: HistoryStoreError
        /// The blob files written (or found in place) before the failure,
        /// still reserved. Hand it to `HistoryStore.discard(_:)`, which
        /// deletes the ones no clip uses, so none waits for the next launch.
        public let written: StagedClip
    }

    let blobs: BlobStore
    /// Payloads larger than this go to blob files (the store's threshold).
    let inlineThreshold: Int

    /// Where `stageInBackground(_:)` writes and flushes files, one clip at a
    /// time, so blocking I/O never holds a thread of Swift's cooperative pool.
    private static let queue = DispatchQueue(label: "app.kept.blob-staging", qos: .userInitiated)

    /// `draft` with every payload over the inline threshold written to its
    /// blob file (flushed to disk) and reserved, so no deletion removes the
    /// file before `HistoryStore.record(_:at:)` commits the clip or
    /// `HistoryStore.discard(_:)` lets it go. Reuses the hashes `ClipBuilder`
    /// worked out. Runs anywhere, blocking until the files are on disk.
    public func stage(_ draft: ClipDraft) throws(Failure) -> StagedClip {
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
                guard let hash = representation.sha256, !written.contains(hash) else { continue }
                do {
                    try blobs.write(representation.data, hash: hash)
                } catch {
                    let partial = StagedClip(draft: draft, blobHashes: written, reservation: reservation)
                    throw Failure(error: error, written: partial)
                }
                written.insert(hash)
            }
        }
        return StagedClip(draft: draft, blobHashes: hashes, reservation: reservation)
    }

    /// `stage(_:)` on a serial queue of the stager's own, so the caller's
    /// thread (one of the cooperative pool's few) isn't blocked while files
    /// are written and flushed.
    public func stageInBackground(_ draft: ClipDraft) async throws(Failure) -> StagedClip {
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<StagedClip, Failure>, Never>) in
            Self.queue.async {
                do throws(Failure) {
                    continuation.resume(returning: .success(try stage(draft)))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
        switch result {
        case .success(let staged): return staged
        case .failure(let failure): throw failure
        }
    }
}
