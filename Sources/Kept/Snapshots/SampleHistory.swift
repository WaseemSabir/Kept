import CoreGraphics
import Foundation
import KeptCore

/// A believable clip history for snapshot renders: prose, rich text, code,
/// links, a color, an image, files and two pins, copied from real apps over
/// the last few weeks. Every clip goes through `ClipBuilder`, as a real copy
/// would.
@MainActor
enum SampleHistory {
    private struct Sample {
        let items: [PasteboardItem]
        let source: String
        let minutesAgo: Double
        var copies = 1
        var pinned = false
    }

    /// Records the samples into `store`, ages measured from `now`.
    static func fill(_ store: HistoryStore, now: Date) throws {
        let builder = ClipBuilder(imageInspector: ImageIOInspector())
        var pins: [UUID] = []
        // Oldest first, so the store orders them as a real history would.
        for sample in samples().sorted(by: { $0.minutesAgo > $1.minutesAgo }) {
            let snapshot = PasteboardSnapshot(items: sample.items, sourceBundleID: sample.source)
            guard let draft = builder.build(from: PasteboardReader.normalized(snapshot)) else {
                throw SampleError(description: "A sample didn't build: \(sample.items)")
            }
            var clip: Clip?
            for copy in 0..<sample.copies {
                // Earlier copies of the same content, a day apart.
                let minutes = sample.minutesAgo + Double(sample.copies - 1 - copy) * 1440
                clip = try store.record(draft, at: now.addingTimeInterval(-minutes * 60))
            }
            if sample.pinned, let clip { pins.append(clip.id) }
        }
        for id in pins {
            try store.pin(id)
        }
    }

    struct SampleError: Error, CustomStringConvertible {
        let description: String
    }

    // MARK: Samples

    private static func samples() -> [Sample] {
        [
            Sample(
                items: [text("Thanks for reaching out! I’ve passed this along to the team, and we’ll get back to you within one business day.")],
                source: "com.apple.mail", minutesAgo: 60 * 24 * 3, copies: 14, pinned: true
            ),
            Sample(
                items: [text("1 Ferry Building, San Francisco, CA 94111")],
                source: "com.apple.Maps", minutesAgo: 60 * 24 * 9, copies: 6, pinned: true
            ),
            Sample(
                items: [text("""
                    Thanks for the quick turnaround on the onboarding flow. Two small notes before we ship: \
                    the empty state should say what to do next, and the shortcut hints need to match the menu.
                    """)],
                source: "com.apple.mail", minutesAgo: 2
            ),
            Sample(
                items: [text("https://developer.apple.com/documentation/appkit/nspasteboard/changecount")],
                source: "com.apple.Safari", minutesAgo: 9, copies: 2
            ),
            Sample(
                items: [PasteboardItem([ClipRepresentation(.png, landscapePNG())])],
                source: "com.apple.Preview", minutesAgo: 26
            ),
            Sample(
                items: [text("""
                    func write(_ items: [NSPasteboardItem]) -> Int {
                        pasteboard.clearContents()
                        pasteboard.writeObjects(items)
                        return pasteboard.changeCount
                    }
                    """)],
                source: "com.apple.dt.Xcode", minutesAgo: 64
            ),
            Sample(
                items: [text("#FF6A00")],
                source: "com.apple.DigitalColorMeter", minutesAgo: 131
            ),
            Sample(
                items: [
                    file("/Users/sam/Documents/Invoices/Invoice-2041.pdf"),
                    file("/Users/sam/Documents/Invoices/Invoice-2042.pdf"),
                    file("/Users/sam/Documents/Invoices/Receipts October.zip"),
                ],
                source: "com.apple.finder", minutesAgo: 252
            ),
            Sample(
                items: [text("git log --oneline --graph --decorate -20")],
                source: "com.apple.Terminal", minutesAgo: 60 * 22
            ),
            Sample(
                items: [richText("Pick up the framed print from the shop on Fifth before 6 pm, then drop the keys at Maya’s.")],
                source: "com.apple.Notes", minutesAgo: 60 * 27
            ),
            Sample(
                items: [text("https://github.com/sindresorhus/KeyboardShortcuts#readme")],
                source: "com.apple.Safari", minutesAgo: 60 * 24 * 2 + 40
            ),
            Sample(
                items: [file("/Users/sam/Desktop/Panel review.key")],
                source: "com.apple.finder", minutesAgo: 60 * 24 * 4
            ),
            Sample(
                items: [text(#"{"id": 2041, "status": "paid", "total": 129.00, "currency": "EUR"}"#)],
                source: "com.apple.Terminal", minutesAgo: 60 * 24 * 6
            ),
            Sample(
                items: [text("rgba(52, 120, 246, 0.5)")],
                source: "com.apple.Safari", minutesAgo: 60 * 24 * 12
            ),
            Sample(
                items: [text("Sam Rivera, Product Design")],
                source: "com.apple.AddressBook", minutesAgo: 60 * 24 * 19
            ),
        ]
    }

    private static func text(_ string: String) -> PasteboardItem {
        PasteboardItem([ClipRepresentation(.string, string: string)])
    }

    private static func richText(_ string: String) -> PasteboardItem {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
            .replacingOccurrences(of: "’", with: "\\'92")
        let rtf = #"{\rtf1\ansi\ansicpg1252{\fonttbl\f0\fswiss Helvetica;}\f0\fs26 "# + escaped + "}"
        return PasteboardItem([
            ClipRepresentation(.rtf, string: rtf),
            ClipRepresentation(.string, string: string),
        ])
    }

    private static func file(_ path: String) -> PasteboardItem {
        PasteboardItem([ClipRepresentation(.fileURL, string: URL(fileURLWithPath: path).absoluteString)])
    }

    // MARK: Image

    /// A 1440 × 900 dusk landscape: sky, sun and two ridges.
    static func landscapePNG(width: Int = 1440, height: Int = 900) -> Data {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return Data() }
        let size = CGSize(width: width, height: height)

        // Sky: deep blue at the top to warm orange at the horizon (y is up).
        let sky = [color(0xF6A65B), color(0xC8607A), color(0x2B2F5C)]
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: sky as CFArray, locations: [0, 0.35, 1]) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: size.height * 0.3),
                end: CGPoint(x: 0, y: size.height),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        context.setFillColor(color(0xFFD84D, alpha: 0.9))
        context.fillEllipse(in: CGRect(x: size.width * 0.62, y: size.height * 0.34, width: 150, height: 150))

        func ridge(_ points: [(CGFloat, CGFloat)], fill: CGColor) {
            context.beginPath()
            context.move(to: CGPoint(x: 0, y: 0))
            for (x, y) in points {
                context.addLine(to: CGPoint(x: size.width * x, y: size.height * y))
            }
            context.addLine(to: CGPoint(x: size.width, y: 0))
            context.closePath()
            context.setFillColor(fill)
            context.fillPath()
        }
        ridge([(0, 0.42), (0.18, 0.55), (0.34, 0.44), (0.52, 0.6), (0.7, 0.43), (0.86, 0.5), (1, 0.4)],
              fill: color(0x5A3E63))
        ridge([(0, 0.26), (0.22, 0.36), (0.4, 0.24), (0.6, 0.33), (0.8, 0.22), (1, 0.3)],
              fill: color(0x2A2140))

        guard let image = context.makeImage() else { return Data() }
        return ImageTranscoder.pngData(from: image) ?? Data()
    }

    private static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
