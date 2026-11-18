import Foundation

/// Reads the pixel size from a PNG's `IHDR` chunk.
public struct PNGImageInspector: ImageInspecting {
    public init() {}

    public func pixelSize(of data: Data, type: PasteboardType) -> PixelSize? {
        let header = [UInt8](data.prefix(24))
        guard header.count == 24,
              header[0..<8].elementsEqual(Self.signature),
              header[12..<16].elementsEqual(Array("IHDR".utf8))
        else { return nil }
        let width = Self.bigEndian(header[16..<20])
        let height = Self.bigEndian(header[20..<24])
        guard width > 0, height > 0 else { return nil }
        return PixelSize(width: width, height: height)
    }

    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private static func bigEndian(_ bytes: ArraySlice<UInt8>) -> Int {
        bytes.reduce(0) { $0 << 8 | Int($1) }
    }
}
