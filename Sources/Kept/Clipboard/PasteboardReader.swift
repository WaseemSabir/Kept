import AppKit
import KeptCore

/// Reads the pasteboard into a `PasteboardSnapshot`.
///
/// It asks `CapturePolicy` about the pasteboard's types and source app
/// first, so content that's marked secret, comes from an excluded app or
/// isn't wanted is never read. A copy of more than `CapturePolicy.maxItems`
/// items is skipped unread. Then it reads, item by item, only what
/// `CapturePolicy.typesToRead(offered:)` allows: the text types, file URLs
/// when files are kept, and one image type when images are kept (a
/// screenshot's TIFF next to its PNG, or a Universal Clipboard photo's
/// second format fetched from the phone, is never loaded).
///
/// Threading: `NSPasteboard` and `NSPasteboardItem` aren't documented as
/// thread-safe, and reading an item can make AppKit fetch promised data
/// from the app that copied, so every pasteboard call stays on the main
/// actor. The work after the read runs off it: `normalized(_:)` resolves
/// Finder's file references and re-encodes TIFF, then capture builds,
/// hashes and writes blob files in the same detached task.
struct PasteboardReader {
    enum ReadResult: Equatable {
        case ignored(IgnoreReason)
        case snapshot(PasteboardSnapshot)
        /// The pasteboard changed while it was being read, so what was read
        /// may mix two copies and skipped the policy check for the second.
        /// The read is dropped; the monitor's next poll sees the new change.
        case changedDuringRead
    }

    /// - Parameter frontmostBundleID: the frontmost app at the time of the
    ///   change; the source when the pasteboard doesn't name one.
    @MainActor
    func read(
        from pasteboard: NSPasteboard,
        settings: CaptureSettings,
        frontmostBundleID: String?
    ) -> ReadResult {
        // Everything below must describe one copy. If another app writes in
        // between (say, a password marked concealed), the types the policy
        // approved no longer match the data, so the change count is checked
        // again at the end.
        let changeCount = pasteboard.changeCount
        let types = (pasteboard.types ?? []).map { PasteboardType(rawValue: $0.rawValue) }
        let policy = CapturePolicy(settings: settings)

        // Markers, pause and the frontmost app decide most copies from the
        // types alone, before even the source marker is read.
        if case .ignore(let reason) = policy.decision(types: types, sourceBundleID: frontmostBundleID) {
            return .ignored(reason)
        }
        let marker = types.contains(.source)
            ? pasteboard.string(forType: NSPasteboard.PasteboardType(PasteboardType.source.rawValue))
            : nil
        let source = PasteboardSnapshot.sourceBundleID(marker: marker, frontmost: frontmostBundleID)
        if source != frontmostBundleID,
           case .ignore(let reason) = policy.decision(types: types, sourceBundleID: source) {
            return .ignored(reason)
        }

        let pasteboardItems = pasteboard.pasteboardItems ?? []
        guard pasteboardItems.count <= CapturePolicy.maxItems else { return .ignored(.tooManyItems) }
        let items = pasteboardItems.compactMap { Self.capturedItem($0, policy: policy) }
        guard pasteboard.changeCount == changeCount else { return .changedDuringRead }
        guard !items.isEmpty else { return .ignored(.empty) }
        // Every declared type goes along, markers included, so the builder
        // can refuse a marked copy on its own as well.
        return .snapshot(PasteboardSnapshot(
            items: items,
            changeCount: changeCount,
            sourceBundleID: source,
            declaredTypes: types
        ))
    }

    /// The item's representations worth reading, in the order the source
    /// app offered them; `nil` when it has none.
    @MainActor
    private static func capturedItem(_ item: NSPasteboardItem, policy: CapturePolicy) -> PasteboardItem? {
        let nativeTypes = item.types
        let wanted = policy.typesToRead(offered: nativeTypes.map { PasteboardType(rawValue: $0.rawValue) })
        var seen = Set<PasteboardType>()
        let representations = nativeTypes.compactMap { nativeType -> ClipRepresentation? in
            let type = PasteboardType(rawValue: nativeType.rawValue)
            guard wanted.contains(type), seen.insert(type).inserted,
                  let data = item.data(forType: nativeType)
            else { return nil }
            return ClipRepresentation(type, data)
        }
        return representations.isEmpty ? nil : PasteboardItem(representations)
    }

    // MARK: Fix-ups, off the main actor

    /// Finder puts file *reference* URLs (`file:///.file/id=…`) on the
    /// pasteboard. They only make sense on this Mac while the file exists, so
    /// they're turned into ordinary path URLs. Anything else is returned as
    /// is. Asks the file system, so it runs off the main actor.
    static func resolvingFileReference(_ data: Data) -> Data {
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        guard text.hasPrefix("file:///.file/id="),
              let url = URL(string: text),
              let pathURL = (url as NSURL).filePathURL
        else { return data }
        return Data(pathURL.absoluteString.utf8)
    }

    /// `snapshot` made ready to build, off the main actor: file reference
    /// URLs resolved to paths, and TIFF-only images re-encoded as PNG, which
    /// is usually several times smaller (items that already offer PNG are
    /// left alone).
    static func normalized(_ snapshot: PasteboardSnapshot) -> PasteboardSnapshot {
        var snapshot = snapshot
        snapshot.items = snapshot.items.map { item in
            var item = item
            for index in item.representations.indices where item.representations[index].type == .fileURL {
                item.representations[index].data = resolvingFileReference(item.representations[index].data)
            }
            guard item.data(for: .png) == nil,
                  let index = item.representations.firstIndex(where: { $0.type == .tiff }),
                  let png = ImageTranscoder.pngData(from: item.representations[index].data)
            else { return item }
            item.representations[index] = ClipRepresentation(.png, png)
            return item
        }
        return snapshot
    }
}
