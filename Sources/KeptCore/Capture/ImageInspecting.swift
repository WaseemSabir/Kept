import Foundation

/// Reads an image's pixel size without decoding it.
///
/// Core only understands PNG (`PNGImageInspector`); the app supplies an
/// ImageIO-backed inspector for TIFF, JPEG and HEIC.
public protocol ImageInspecting: Sendable {
    func pixelSize(of data: Data, type: PasteboardType) -> PixelSize?
}
