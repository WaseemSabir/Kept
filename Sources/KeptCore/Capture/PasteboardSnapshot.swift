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

    public init(items: [PasteboardItem], changeCount: Int = 0, sourceBundleID: String? = nil) {
        self.items = items
        self.changeCount = changeCount
        self.sourceBundleID = sourceBundleID
    }

    /// Every type across all items, in first-seen order. `NSPasteboard.types`
    /// reports the same union.
    public var types: [PasteboardType] {
        var seen = Set<PasteboardType>()
        return items.flatMap(\.types).filter { seen.insert($0).inserted }
    }

    /// The source app: the `org.nspasteboard.source` marker when it names
    /// one, else the frontmost app at the time of the change.
    public static func sourceBundleID(marker: String?, frontmost: String?) -> String? {
        if let marker = marker?.trimmingCharacters(in: .whitespacesAndNewlines), !marker.isEmpty {
            return marker
        }
        return frontmost
    }
}
