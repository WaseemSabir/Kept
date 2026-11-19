import AppKit
import KeptCore

extension NSPasteboard.PasteboardType {
    /// The AppKit pasteboard type for one of Kept's; both are named by the
    /// same UTI string.
    init(_ type: KeptCore.PasteboardType) {
        self.init(type.rawValue)
    }
}
