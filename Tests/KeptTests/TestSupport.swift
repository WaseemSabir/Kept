import AppKit
import ImageIO
@testable import Kept
import KeptCore

struct TestSetupError: Error, CustomStringConvertible {
    let description: String
}

/// A fresh, empty folder under the temporary directory.
func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("KeptTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func removeTemporaryDirectory(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

/// A draft for plain text, built the way capture builds it.
func textDraft(_ text: String, source: String? = nil) throws -> ClipDraft {
    let snapshot = PasteboardSnapshot(
        items: [PasteboardItem([ClipRepresentation(.string, string: text)])],
        sourceBundleID: source
    )
    guard let draft = ClipBuilder().build(from: snapshot) else {
        throw TestSetupError(description: "No draft for \(text)")
    }
    return draft
}

extension Date {
    /// A fixed point in time plus `seconds`, so ordering tests are deterministic.
    static func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
    }
}

/// A store in `directory` holding `texts`, the first one newest.
@MainActor
func makeStore(in directory: URL, texts: [String]) throws -> HistoryStore {
    let store = try HistoryStore(directory: directory)
    for (offset, text) in texts.reversed().enumerated() {
        try store.record(try textDraft(text), at: .at(Double(offset)))
    }
    return store
}

/// Records what the panel asked to paste instead of touching a pasteboard.
@MainActor
final class RecordingPaster: ClipPasting {
    struct Paste: Equatable {
        let title: String
        let request: PasteRequest
    }

    private(set) var pastes: [Paste] = []
    private(set) var completed: [PastePlan] = []
    private(set) var anchors: [CGRect?] = []
    var failure: (any Error)?
    /// What `prepare` returns.
    var plan = PastePlan.paste(plainText: false)
    /// Shared with the panel's `onDismiss`, to check what happens first.
    var log: EventLog?

    func prepare(_ clip: Clip, for request: PasteRequest) throws -> PastePlan {
        if let failure { throw failure }
        pastes.append(Paste(title: clip.title, request: request))
        log?.events.append("prepare")
        return plan
    }

    func complete(_ plan: PastePlan, anchor: CGRect?) {
        completed.append(plan)
        anchors.append(anchor)
        log?.events.append("complete")
    }
}

/// The order things happened in, across objects.
@MainActor
final class EventLog {
    var events: [String] = []
}

/// A private, uniquely named pasteboard, so tests never touch the user's
/// clipboard. Release it with `releaseGlobally()`.
@MainActor
func makePasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("app.kept.tests.\(UUID().uuidString)"))
}

extension NSPasteboard {
    /// Replaces the contents with `string` (plus empty marker types), the way
    /// another app's copy would, and returns the new change count.
    @discardableResult
    func simulateCopy(_ string: String, markers: [KeptCore.PasteboardType] = []) -> Int {
        let changeCount = clearContents()
        let item = NSPasteboardItem()
        item.setString(string, forType: .string)
        for marker in markers {
            item.setString(marker == .source ? "com.apple.TextEdit" : "1", forType: NSPasteboard.PasteboardType(marker.rawValue))
        }
        writeObjects([item])
        return changeCount
    }
}

/// A `width` × `height` image of one color, encoded as `type` (a UTI).
func encodedImage(width: Int, height: Int, type: String) throws -> Data {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else { throw TestSetupError(description: "No bitmap context") }
    context.setFillColor(CGColor(srgbRed: 1, green: 0.85, blue: 0.3, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let output = NSMutableData()
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithData(output as CFMutableData, type as CFString, 1, nil)
    else { throw TestSetupError(description: "No image destination for \(type)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw TestSetupError(description: "Couldn't encode \(type)")
    }
    return output as Data
}
