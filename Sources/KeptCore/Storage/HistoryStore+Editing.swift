import Foundation

/// Renaming a clip and editing its text.
@MainActor
extension HistoryStore {
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
        let staged = try stage(draft)
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
                // Replaces the duplicate too, and any unreadable row with the
                // same content.
                try write(edited, representations: representations)
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
}
