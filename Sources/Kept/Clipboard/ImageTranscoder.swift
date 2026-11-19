import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ImageIO helpers for capture and display. ImageIO is thread-safe, so these
/// run off the main actor for big images.
enum ImageTranscoder {
    /// `data` (TIFF, JPEG, HEIC… any format ImageIO reads) re-encoded as PNG,
    /// first frame only; `nil` when it can't be decoded.
    static func pngData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// A downsampled image whose longer side is at most `maxPixelSize`,
    /// rotated upright; `nil` when `data` isn't an image.
    static func thumbnail(of data: Data, maxPixelSize: Int) -> DecodedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return DecodedImage(cgImage: image)
    }

    /// PNG data for `image`.
    static func pngData(from image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// A decoded image that can cross actors. `CGImage` is immutable, so sharing
/// it is safe.
struct DecodedImage: @unchecked Sendable {
    let cgImage: CGImage
}
