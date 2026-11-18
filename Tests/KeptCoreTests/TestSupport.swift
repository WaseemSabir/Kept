import Foundation
@testable import KeptCore

/// A fresh, empty folder under the temporary directory. Delete it with
/// `removeTemporaryDirectory(_:)`.
func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("KeptCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func removeTemporaryDirectory(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

/// A pasteboard item from `(type, string)` pairs.
func item(_ representations: (PasteboardType, String)...) -> PasteboardItem {
    PasteboardItem(representations.map { ClipRepresentation($0.0, string: $0.1) })
}

/// A snapshot of one item holding `text` as a plain string.
func textSnapshot(_ text: String, source: String? = nil) -> PasteboardSnapshot {
    PasteboardSnapshot(items: [item((.string, text))], sourceBundleID: source)
}

/// Bytes that start like a PNG of the given size (signature + IHDR), padded
/// to `byteCount` with a repeating pattern seeded by `seed`.
func pngData(width: Int, height: Int, byteCount: Int = 64, seed: UInt8 = 0) -> Data {
    var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13]
    bytes += Array("IHDR".utf8)
    for value in [width, height] {
        bytes += [UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)]
    }
    bytes += [8, 6, 0, 0, 0, 0, 0, 0, 0]
    var next = seed
    while bytes.count < byteCount {
        bytes.append(next)
        next &+= 31
    }
    return Data(bytes)
}

/// A draft for plain text, built the way capture builds it.
func textDraft(_ text: String, source: String? = nil) -> ClipDraft {
    guard let draft = ClipBuilder().build(from: textSnapshot(text, source: source)) else {
        fatalError("No draft for \(text)")
    }
    return draft
}

extension Date {
    /// A fixed point in time plus `seconds`, so ordering tests are deterministic.
    static func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
    }
}
