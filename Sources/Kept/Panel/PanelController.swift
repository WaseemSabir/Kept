import AppKit
import SwiftUI

/// Owns the floating panel: builds its content, places it, and shows or hides
/// it without activating Kept.
@MainActor
final class PanelController {
    private let panel: FloatingPanel

    init() {
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: Theme.Layout.panelSize))
        panel.contentView = Self.makeContentView()
        panel.onResignKey = { [weak self] in self?.hide() }
        panel.onCancel = { [weak self] in self?.hide() }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Shows the panel centered on the screen under the mouse and makes it
    /// key. `orderFrontRegardless` + `makeKey` (rather than activating Kept)
    /// keeps the user's app frontmost.
    func show() {
        center(on: screenUnderMouse())
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    // MARK: Placement

    private func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
    }

    private func center(on screen: NSScreen?) {
        guard let visibleFrame = screen?.visibleFrame else {
            panel.center()
            return
        }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: (visibleFrame.midX - size.width / 2).rounded(),
            y: (visibleFrame.midY - size.height / 2).rounded()
        ))
    }

    // MARK: Content

    /// SwiftUI content on a vibrancy background that fills the whole panel,
    /// including the hidden title bar area.
    private static func makeContentView() -> NSView {
        let background = NSVisualEffectView()
        background.material = Theme.Layout.panelMaterial
        background.blendingMode = .behindWindow
        background.state = .active

        let hostingView = NSHostingView(rootView: PanelView().ignoresSafeArea())
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: background.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        return background
    }
}
