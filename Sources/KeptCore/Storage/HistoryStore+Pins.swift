import Foundation

/// Pinning, unpinning and reordering pins. Pins are numbered 0, 1, 2… in
/// the database as in `pinned`.
@MainActor
extension HistoryStore {
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

    /// Renumbers `pins` 0, 1, 2… in the database and in place.
    func writePinOrder(_ pins: inout [Clip]) throws {
        let statement = try database.prepare("UPDATE clips SET pin_order = ? WHERE id = ?")
        for index in pins.indices where pins[index].pinOrder != index {
            try statement.bind(index, at: 1)
            try statement.bind(pins[index].id.uuidString, at: 2)
            try statement.run()
            try statement.reset()
            pins[index].pinOrder = index
        }
    }
}
