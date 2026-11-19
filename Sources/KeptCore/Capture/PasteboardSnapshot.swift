import Foundation

/// A platform-neutral copy of what was on the pasteboard after one change.
///
/// The app builds it from `NSPasteboard` (reading only
/// `PasteboardType.captured`); tests build it by hand.
public struct PasteboardSnapshot: Sendable, Hashable {
    public var items: [PasteboardItem]
    /// `NSPasteboard.changeCount` when the snapshot was taken.
    public var changeCount: Int
    /// The app that wrote the pasteboard. Resolve it with
    /// `sourceBundleID(marker:frontmost:)`.
    public var sourceBundleID: String?
    /// Every type the pasteboard declared (`NSPasteboard.types`), including
    /// markers whose data was never read, such as
    /// `org.nspasteboard.ConcealedType`. `CapturePolicy.decision(for:)` and
    /// `ClipBuilder` check it as well as the items, so a privacy marker
    /// stops capture even though the app reads only captured types.
    public var declaredTypes: [PasteboardType]

    /// - Parameter declaredTypes: what `NSPasteboard.types` reported; `nil`
    ///   (the default) uses the union of the items' types.
    public init(
        items: [PasteboardItem],
        changeCount: Int = 0,
        sourceBundleID: String? = nil,
        declaredTypes: [PasteboardType]? = nil
    ) {
        self.items = items
        self.changeCount = changeCount
        self.sourceBundleID = sourceBundleID
        self.declaredTypes = declaredTypes ?? Self.union(of: items)
    }

    /// Every type across all items, in first-seen order. `NSPasteboard.types`
    /// reports the same union.
    public var types: [PasteboardType] {
        Self.union(of: items)
    }

    /// `declaredTypes` and the items' types together, in first-seen order.
    public var allTypes: [PasteboardType] {
        var seen = Set<PasteboardType>()
        return (declaredTypes + items.flatMap(\.types)).filter { seen.insert($0).inserted }
    }

    /// The source app: the `org.nspasteboard.source` marker when it names
    /// one, else the frontmost app at the time of the change.
    public static func sourceBundleID(marker: String?, frontmost: String?) -> String? {
        if let marker = marker?.trimmingCharacters(in: .whitespacesAndNewlines), !marker.isEmpty {
            return marker
        }
        return frontmost
    }

    private static func union(of items: [PasteboardItem]) -> [PasteboardType] {
        var seen = Set<PasteboardType>()
        return items.flatMap(\.types).filter { seen.insert($0).inserted }
    }
}
