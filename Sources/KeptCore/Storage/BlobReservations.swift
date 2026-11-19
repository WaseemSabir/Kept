import Foundation

/// Blob files that a capture has written, or is writing, off the main actor
/// but the history hasn't recorded yet, so nothing deletes them in between.
///
/// Every deletion in `BlobStore` asks `unlessReserved(_:_:)`, which holds
/// the same lock as `reserve(_:)`, so a deletion and a reservation of the
/// same hash can't interleave: either the file goes first (and the capture
/// then writes it again), or the reservation comes first and the file stays.
/// Orphans left by a capture that's never recorded are swept at the next
/// launch, or as soon as `HistoryStore.discard(_:)` lets them go.
final class BlobReservations: @unchecked Sendable {
    /// Keeps a set of hashes reserved until `release()` or until it's freed.
    final class Reservation: @unchecked Sendable {
        let hashes: Set<String>
        private let owner: BlobReservations
        /// Guarded by `owner.lock`.
        private var isReleased = false

        fileprivate init(hashes: Set<String>, owner: BlobReservations) {
            self.hashes = hashes
            self.owner = owner
        }

        /// Ends the reservation. Calling it again does nothing.
        func release() {
            owner.lock.lock()
            defer { owner.lock.unlock() }
            guard !isReleased else { return }
            isReleased = true
            for hash in hashes {
                if let count = owner.counts[hash], count > 1 {
                    owner.counts[hash] = count - 1
                } else {
                    owner.counts[hash] = nil
                }
            }
        }

        deinit {
            release()
        }
    }

    private let lock = NSLock()
    /// How many reservations hold each hash.
    private var counts: [String: Int] = [:]

    /// Reserves `hashes` until the returned reservation is released.
    func reserve(_ hashes: Set<String>) -> Reservation {
        lock.lock()
        defer { lock.unlock() }
        for hash in hashes {
            counts[hash, default: 0] += 1
        }
        return Reservation(hashes: hashes, owner: self)
    }

    func isReserved(_ hash: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return counts[hash] != nil
    }

    /// Runs `body` (which deletes the file for `hash`) unless `hash` is
    /// reserved, holding the lock throughout. Returns whether it ran.
    @discardableResult
    func unlessReserved<Failure: Error>(_ hash: String, _ body: () throws(Failure) -> Void) throws(Failure) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard counts[hash] == nil else { return false }
        try body()
        return true
    }
}
