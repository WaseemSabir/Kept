import Foundation

/// One pasteboard type of a clip and its bytes, e.g. `public.rtf` and the
/// RTF document.
public struct ClipRepresentation: Sendable, Hashable {
    public var type: PasteboardType
    public var data: Data

    public init(_ type: PasteboardType, _ data: Data) {
        self.type = type
        self.data = data
    }

    /// A representation holding `string` as UTF-8.
    public init(_ type: PasteboardType, string: String) {
        self.init(type, Data(string.utf8))
    }
}
