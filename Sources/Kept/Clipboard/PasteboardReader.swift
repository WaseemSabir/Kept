import AppKit
import KeptCore

/// Reads the pasteboard into a `PasteboardSnapshot`.
///
/// It asks `CapturePolicy` about the pasteboard's types and source app
/// first, so content that's marked secret, comes from an excluded app or
/// isn't wanted is never read. Then it reads only the types Kept stores
/// (`PasteboardType.captured`), item by item.
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

        let items = (pasteboard.pasteboardItems ?? []).compactMap { Self.capturedItem($0) }
        guard pasteboard.changeCount == changeCount else { return .changedDuringRead }
        guard !items.isEmpty else { return .ignored(.empty) }
        return .snapshot(PasteboardSnapshot(
            items: items,
            changeCount: changeCount,
            sourceBundleID: source
        ))
    }

    /// The item's captured representations in the order the source app
    /// offered them; `nil` when it has none.
    @MainActor
    private static func capturedItem(_ item: NSPasteboardItem) -> PasteboardItem? {
        var seen = Set<PasteboardType>()
        let representations = item.types.compactMap { nativeType -> ClipRepresentation? in
            let type = PasteboardType(rawValue: nativeType.rawValue)
            guard capturedTypes.contains(type), seen.insert(type).inserted,
                  let data = item.data(forType: nativeType)
            else { return nil }
            return ClipRepresentation(type, type == .fileURL ? resolvingFileReference(data) : data)
        }
        return representations.isEmpty ? nil : PasteboardItem(representations)
    }

    private static let capturedTypes = Set(PasteboardType.captured)

    // MARK: Fix-ups

    /// Finder puts file *reference* URLs (`file:///.file/id=…`) on the
    /// pasteboard. They only make sense on this Mac while the file exists, so
    /// they're turned into ordinary path URLs. Anything else is returned as is.
    static func resolvingFileReference(_ data: Data) -> Data {
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        guard text.hasPrefix("file:///.file/id="),
              let url = URL(string: text),
              let pathURL = (url as NSURL).filePathURL
        else { return data }
        return Data(pathURL.absoluteString.utf8)
    }

    /// `snapshot` with TIFF-only images re-encoded as PNG, which is usually
    /// several times smaller. Items that already offer PNG are left alone.
    /// Runs off the main actor, before the clip is built.
    static func normalized(_ snapshot: PasteboardSnapshot) -> PasteboardSnapshot {
        var snapshot = snapshot
        snapshot.items = snapshot.items.map { item in
            guard item.data(for: .png) == nil,
                  let index = item.representations.firstIndex(where: { $0.type == .tiff }),
                  let png = ImageTranscoder.pngData(from: item.representations[index].data)
            else { return item }
            var item = item
            item.representations[index] = ClipRepresentation(.png, png)
            return item
        }
        return snapshot
    }
}
