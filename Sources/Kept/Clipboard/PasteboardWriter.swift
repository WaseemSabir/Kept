import AppKit
import KeptCore

/// Writes a clip's pasteboard items back to the pasteboard.
///
/// Every write carries Kept's own marker (`PasteboardType.keptOwn`) and, when
/// known, the original app in `org.nspasteboard.source`, so neither Kept nor
/// other clipboard managers record it as a new copy.
@MainActor
struct PasteboardWriter {
    let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    /// Replaces the pasteboard's contents with `items`, one pasteboard item
    /// each (multi-file pastes need separate items). `markers` (privacy
    /// markers such as `.concealed`) go on the first item, so other
    /// clipboard managers skip the write too. Returns the pasteboard's new
    /// change count, or `nil` when nothing was written.
    func write(_ items: [PasteboardItem], sourceBundleID: String?, markers: [PasteboardType] = []) -> Int? {
        let objects = items
            .filter { !$0.representations.isEmpty }
            .map { item -> NSPasteboardItem in
                let object = NSPasteboardItem()
                for representation in item.representations {
                    object.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type))
                }
                return object
            }
        guard let first = objects.first else { return nil }
        // A non-empty value: some pasteboard readers drop empty types.
        for marker in [PasteboardType.keptOwn] + markers {
            first.setString("1", forType: NSPasteboard.PasteboardType(marker))
        }
        if let sourceBundleID, !sourceBundleID.isEmpty {
            first.setString(sourceBundleID, forType: NSPasteboard.PasteboardType(PasteboardType.source))
        }

        pasteboard.clearContents()
        guard pasteboard.writeObjects(objects) else { return nil }
        return pasteboard.changeCount
    }
}
