import AppKit

/// Kept's menu bar glyph: a short list whose middle line is marked with a
/// highlighter, the app icon reduced to a monochrome template image. The
/// marker is solid while Kept captures and hollow while capture is paused.
///
/// Drawn on demand on a 20 × 18 pt grid (y down), so it's crisp at every
/// backing scale. Every edge except the marker's slanted ends sits on a
/// whole point. See the Icon section of docs/DESIGN.md.
enum MenuBarIcon {
    static let size = NSSize(width: 20, height: 18)

    /// A template image for the status item; AppKit tints it for the menu bar.
    static func image(paused: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: context, paused: paused)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = paused ? "Kept, capture paused" : "Kept"
        return image
    }

    private static func draw(in context: CGContext, paused: Bool) {
        let black = CGColor(gray: 0, alpha: 1)
        context.setFillColor(black)
        context.setStrokeColor(black)

        context.addPath(line(x: 4, y: 2, width: 10))
        context.addPath(line(x: 4, y: 14, width: 7))
        context.fillPath()

        let marker = markerPath()
        let markedLine = line(x: 4, y: 8, width: 11)
        if paused {
            // Hollow: a 1 pt outline inside the marker, the line drawn in it.
            context.saveGState()
            context.addPath(marker)
            context.clip()
            context.addPath(marker)
            context.setLineWidth(2)
            context.strokePath()
            context.restoreGState()
            context.addPath(markedLine)
            context.fillPath()
        } else {
            // Solid: the marker with the line knocked out of it.
            context.addPath(marker)
            context.addPath(markedLine)
            context.fillPath(using: .evenOdd)
        }
    }

    /// A chisel-tip swipe, 6 pt tall, both ends cut at the same angle.
    private static func markerPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 3, y: 6))
        path.addLine(to: CGPoint(x: 19, y: 6))
        path.addLine(to: CGPoint(x: 17, y: 12))
        path.addLine(to: CGPoint(x: 1, y: 12))
        path.closeSubpath()
        return path
    }

    /// A 2 pt line of "text" with round ends.
    private static func line(x: CGFloat, y: CGFloat, width: CGFloat) -> CGPath {
        CGPath(
            roundedRect: CGRect(x: x, y: y, width: width, height: 2),
            cornerWidth: 1,
            cornerHeight: 1,
            transform: nil
        )
    }
}
