import Foundation
import ImageIO
import KeptCore

/// Reads an image's pixel size with ImageIO, which understands TIFF, JPEG and
/// HEIC as well as PNG, without decoding the pixels.
struct ImageIOInspector: ImageInspecting {
    func pixelSize(of data: Data, type: PasteboardType) -> PixelSize? {
        // The PNG header is cheaper to read than an image source.
        if let size = PNGImageInspector().pixelSize(of: data, type: type) {
            return size
        }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0
        else { return nil }

        // EXIF orientations 5–8 rotate the image a quarter turn.
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return orientation >= 5
            ? PixelSize(width: height, height: width)
            : PixelSize(width: width, height: height)
    }
}
