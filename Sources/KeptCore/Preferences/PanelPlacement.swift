import Foundation

/// Where the panel goes on screen for each `PanelPosition`.
///
/// Pure geometry in AppKit's screen coordinates (y grows upward; frames as
/// `NSScreen` reports them), so tests can lay out any arrangement of
/// screens. The panel always ends up inside the chosen screen's visible
/// frame (below the menu bar, beside the Dock) when it fits there.
public enum PanelPlacement {
    /// One display: its whole frame and the part not covered by the menu
    /// bar and the Dock.
    public struct Screen: Equatable, Sendable {
        public var frame: CGRect
        public var visibleFrame: CGRect

        public init(frame: CGRect, visibleFrame: CGRect) {
            self.frame = frame
            self.visibleFrame = visibleFrame
        }
    }

    /// The space kept between the panel and the sides and bottom of the
    /// visible frame when the panel is pushed back on screen.
    public static let screenMargin: CGFloat = 8
    /// The gap between the bottom of the menu bar icon and the panel.
    public static let statusItemGap: CGFloat = 4

    /// The panel's frame.
    /// - Parameters:
    ///   - position: where the user wants it.
    ///   - size: the panel's size.
    ///   - screens: every display, the primary (menu bar) one first.
    ///   - mouse: the pointer's location (`NSEvent.mouseLocation`).
    ///   - statusItem: the menu bar icon's frame on screen, or `nil` when
    ///     it isn't showing (macOS can hide it); `.statusItem` then falls
    ///     back to the center of the active screen.
    /// - Returns: `nil` only when there are no screens.
    public static func frame(
        for position: PanelPosition,
        size: CGSize,
        screens: [Screen],
        mouse: CGPoint,
        statusItem: CGRect?
    ) -> CGRect? {
        switch position {
        case .activeScreenCenter:
            guard let screen = screen(containing: mouse, in: screens) else { return nil }
            return centered(size: size, in: screen.visibleFrame)
        case .mouse:
            guard let screen = screen(containing: mouse, in: screens) else { return nil }
            // The top-left corner at the pointer, like a context menu.
            let origin = CGPoint(x: mouse.x, y: mouse.y - size.height)
            return clamped(CGRect(origin: origin, size: size), to: screen.visibleFrame)
        case .statusItem:
            guard let statusItem,
                  let screen = screens.first(where: { contains($0.frame, CGPoint(x: statusItem.midX, y: statusItem.midY)) })
            else {
                return frame(for: .activeScreenCenter, size: size, screens: screens, mouse: mouse, statusItem: nil)
            }
            // Leading edges lined up, like the icon's menu, just below the
            // menu bar.
            let top = min(statusItem.minY, screen.visibleFrame.maxY) - statusItemGap
            let origin = CGPoint(x: statusItem.minX, y: top - size.height)
            return clamped(CGRect(origin: origin, size: size), to: screen.visibleFrame)
        }
    }

    /// The screen under `point`, else the one nearest to it, else the
    /// first.
    static func screen(containing point: CGPoint, in screens: [Screen]) -> Screen? {
        if let screen = screens.first(where: { contains($0.frame, point) }) { return screen }
        return screens.min { distance(from: point, to: $0.frame) < distance(from: point, to: $1.frame) }
    }

    /// `size` centered in `area`, on whole points.
    static func centered(size: CGSize, in area: CGRect) -> CGRect {
        let origin = CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2)
        return clamped(CGRect(origin: origin, size: size), to: area)
    }

    /// Moves `frame` inside `area`, a margin away from its sides and bottom
    /// when there's room for one. A panel wider than `area` is centered
    /// across it; one taller is pinned to the top, so the search field stays
    /// on screen.
    static func clamped(_ frame: CGRect, to area: CGRect) -> CGRect {
        var origin = frame.origin
        let size = frame.size

        if size.width <= area.width {
            let margin = size.width + 2 * screenMargin <= area.width ? screenMargin : 0
            origin.x = min(max(origin.x, area.minX + margin), area.maxX - margin - size.width)
        } else {
            origin.x = area.midX - size.width / 2
        }

        if size.height <= area.height {
            // No margin at the top: that's the menu bar, and the panel may
            // hang right below it.
            let margin = size.height + screenMargin <= area.height ? screenMargin : 0
            origin.y = min(max(origin.y, area.minY + margin), area.maxY - size.height)
        } else {
            origin.y = area.maxY - size.height
        }

        return CGRect(origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size)
    }

    /// Whether `point` is inside `rect`, edges included: the pointer can sit
    /// on a screen's top or right edge.
    private static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx: CGFloat = max(rect.minX - point.x, CGFloat(0), point.x - rect.maxX)
        let dy: CGFloat = max(rect.minY - point.y, CGFloat(0), point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
