import AppKit
import SwiftUI

/// The copy-only hint's window: a small borderless, non-activating panel
/// on the panel's vibrancy, with rounded corners and the system shadow.
///
/// It never becomes key, so the app the user is pasting into keeps the
/// keyboard and ⌘V goes there; its button still takes clicks.
final class HintPanel: NSPanel {
    private let hostingView: FirstMouseHostingView<PasteHintView>

    init() {
        hostingView = FirstMouseHostingView(rootView: PasteHintView(hint: .pressCommandV, permissionDetail: ""))
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        title = "Kept"

        let background = NSVisualEffectView()
        background.material = Theme.Layout.hintMaterial
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: Theme.Layout.hintCornerRadius)
        // Only the content's ideal size, as `fittingSize`; the window's
        // frame is set by the controller, not by the hosting view.
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: background.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        contentView = background
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HintPanel is created in code, not loaded from an archive.")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows `view` and returns the size it needs.
    func setContent(_ view: PasteHintView) -> CGSize {
        hostingView.rootView = view
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }

    /// A stretchable rounded rectangle for the vibrancy view's mask, so the
    /// blur, and the shadow that follows it, have rounded corners.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Takes the first click even though its window never becomes key, so the
/// hint's button works with one click.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
