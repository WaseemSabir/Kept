import Foundation

/// One item on the pasteboard: its representations in the order the source
/// app offered them, richest first.
///
/// Most copies have one item; Finder writes one item per file.
public struct PasteboardItem: Sendable, Hashable {
    public var representations: [ClipRepresentation]

    public init(_ representations: [ClipRepresentation]) {
        self.representations = representations
    }

    public var types: [PasteboardType] {
        representations.map(\.type)
    }

    /// The bytes of the first representation of `type`.
    public func data(for type: PasteboardType) -> Data? {
        representations.first { $0.type == type }?.data
    }

    /// Total bytes across all representations.
    public var byteSize: Int {
        representations.reduce(0) { $0 + $1.data.count }
    }
}
