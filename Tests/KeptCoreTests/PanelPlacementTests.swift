import Foundation
import Testing
@testable import KeptCore

@Suite("Panel placement")
struct PanelPlacementTests {
    private let size = CGSize(width: 720, height: 460)

    /// A 1440 × 900 laptop screen: a 24 pt menu bar on top, a 70 pt Dock below.
    private let laptop = PanelPlacement.Screen(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 806)
    )
    /// A 2560 × 1440 display to the right of the laptop, a little higher, no Dock.
    private let external = PanelPlacement.Screen(
        frame: CGRect(x: 1440, y: 200, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1440, y: 200, width: 2560, height: 1415)
    )

    private func frame(
        _ position: PanelPosition,
        screens: [PanelPlacement.Screen]? = nil,
        mouse: CGPoint,
        statusItem: CGRect? = nil,
        size: CGSize? = nil
    ) -> CGRect? {
        PanelPlacement.frame(
            for: position,
            size: size ?? self.size,
            screens: screens ?? [laptop, external],
            mouse: mouse,
            statusItem: statusItem
        )
    }

    // MARK: Center of the active screen

    @Test("Centers on the visible part of the screen under the pointer")
    func centersOnActiveScreen() {
        let onLaptop = frame(.activeScreenCenter, mouse: CGPoint(x: 100, y: 100))
        #expect(onLaptop == CGRect(x: 360, y: 243, width: 720, height: 460))

        let onExternal = frame(.activeScreenCenter, mouse: CGPoint(x: 3000, y: 900))
        #expect(onExternal == CGRect(x: 2360, y: 678, width: 720, height: 460))
    }

    @Test("A pointer on a screen's top or right edge still counts as on it")
    func edgesCount() {
        let topEdge = frame(.activeScreenCenter, screens: [laptop], mouse: CGPoint(x: 700, y: 900))
        #expect(topEdge?.minY == 243)
        let rightEdge = frame(.activeScreenCenter, mouse: CGPoint(x: 4000, y: 1640))
        #expect(rightEdge?.minX == 2360)
    }

    @Test("A pointer off every screen uses the nearest one")
    func nearestScreen() {
        // Below the external display, right of the laptop.
        let placed = frame(.activeScreenCenter, mouse: CGPoint(x: 3000, y: 50))
        #expect(placed?.minX == 2360)
    }

    @Test("No screens, no frame")
    func noScreens() {
        #expect(frame(.activeScreenCenter, screens: [], mouse: .zero) == nil)
        #expect(frame(.mouse, screens: [], mouse: .zero) == nil)
        #expect(frame(.statusItem, screens: [], mouse: .zero, statusItem: CGRect(x: 0, y: 0, width: 20, height: 24)) == nil)
    }

    // MARK: At the mouse pointer

    @Test("Puts the top-left corner at the pointer")
    func atPointer() {
        let placed = frame(.mouse, mouse: CGPoint(x: 200, y: 700))
        #expect(placed == CGRect(x: 200, y: 240, width: 720, height: 460))
    }

    @Test("Stays on screen near the pointer's edges")
    func pointerClamps() {
        // Bottom right of the laptop: pushed left and up, a margin from the
        // side and the Dock.
        let bottomRight = frame(.mouse, screens: [laptop], mouse: CGPoint(x: 1400, y: 100))
        #expect(bottomRight == CGRect(x: 712, y: 78, width: 720, height: 460))

        // In the menu bar: pushed right below it.
        let inMenuBar = frame(.mouse, screens: [laptop], mouse: CGPoint(x: 10, y: 890))
        #expect(inMenuBar == CGRect(x: 10, y: 416, width: 720, height: 460))
    }

    @Test("Follows the pointer onto another screen")
    func pointerOnOtherScreen() {
        let placed = frame(.mouse, mouse: CGPoint(x: 1500, y: 1000))
        #expect(placed == CGRect(x: 1500, y: 540, width: 720, height: 460))
    }

    // MARK: Below the menu bar icon

    @Test("Hangs below the menu bar icon, leading edges lined up")
    func belowStatusItem() {
        let icon = CGRect(x: 1000, y: 876, width: 28, height: 24)
        let placed = frame(.statusItem, mouse: CGPoint(x: 3000, y: 900), statusItem: icon)
        #expect(placed == CGRect(x: 712, y: 412, width: 720, height: 460))

        let leftIcon = CGRect(x: 300, y: 876, width: 28, height: 24)
        #expect(frame(.statusItem, mouse: .zero, statusItem: leftIcon) == CGRect(x: 300, y: 412, width: 720, height: 460))
    }

    @Test("Uses the screen whose menu bar holds the icon")
    func statusItemOnExternalScreen() {
        let icon = CGRect(x: 3600, y: 1615, width: 28, height: 25)
        let placed = frame(.statusItem, mouse: CGPoint(x: 100, y: 100), statusItem: icon)
        #expect(placed == CGRect(x: 3272, y: 1151, width: 720, height: 460))
    }

    @Test("Without a visible icon, falls back to the center of the active screen")
    func statusItemFallback() {
        let hidden = frame(.statusItem, mouse: CGPoint(x: 100, y: 100), statusItem: nil)
        #expect(hidden == frame(.activeScreenCenter, mouse: CGPoint(x: 100, y: 100)))

        let offScreen = CGRect(x: -5000, y: -5000, width: 28, height: 24)
        let placed = frame(.statusItem, mouse: CGPoint(x: 100, y: 100), statusItem: offScreen)
        #expect(placed == hidden)
    }

    // MARK: Small screens

    @Test("A panel taller or wider than the screen keeps its top on screen")
    func smallScreen() {
        let small = PanelPlacement.Screen(
            frame: CGRect(x: 0, y: 0, width: 640, height: 400),
            visibleFrame: CGRect(x: 0, y: 0, width: 640, height: 376)
        )
        for position in PanelPosition.allCases {
            let placed = frame(
                position,
                screens: [small],
                mouse: CGPoint(x: 600, y: 20),
                statusItem: CGRect(x: 560, y: 376, width: 24, height: 24)
            )
            #expect(placed == CGRect(x: -40, y: -84, width: 720, height: 460), "\(position)")
        }
    }

    @Test("A panel that only just fits drops the margin rather than leave the screen")
    func justFits() {
        let snug = PanelPlacement.Screen(
            frame: CGRect(x: 0, y: 0, width: 730, height: 500),
            visibleFrame: CGRect(x: 0, y: 0, width: 730, height: 470)
        )
        let placed = frame(.mouse, screens: [snug], mouse: CGPoint(x: 700, y: 30))
        #expect(placed == CGRect(x: 10, y: 8, width: 720, height: 460))
    }

    @Test("Origins land on whole points")
    func wholePoints() {
        let odd = CGSize(width: 721, height: 461)
        let placed = frame(.activeScreenCenter, mouse: CGPoint(x: 100, y: 100), size: odd)
        #expect(placed?.minX == placed?.minX.rounded())
        #expect(placed?.minY == placed?.minY.rounded())
    }
}
