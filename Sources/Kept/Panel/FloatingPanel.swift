import AppKit
import Carbon.HIToolbox

/// A non-activating panel that floats above other apps.
///
/// It becomes key, so its search field gets the keyboard, without activating
/// Kept: the app the user was typing in stays frontmost, ready for a paste.
final class FloatingPanel: NSPanel {
    /// Called after the panel stops being key, e.g. after a click elsewhere.
    var onResignKey: (@MainActor () -> Void)?
    /// Called when the user presses Esc.
    var onCancel: (@MainActor () -> Void)?

    init(contentRect: NSRect) {
        // `.nonactivatingPanel` only takes effect when passed to the initializer.
        // `.titled` + `.fullSizeContentView` give the system's rounded corners
        // and shadow; the title bar itself is hidden below.
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        isMovable = false

        title = "Kept" // Not drawn, but read by VoiceOver.
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FloatingPanel is created in code, not loaded from an archive.")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    /// Esc closes the panel whichever view has focus, unless an input method
    /// is composing text, in which case Esc belongs to the input method.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == UInt16(kVK_Escape), !isComposingText {
            onCancel?()
            return
        }
        super.sendEvent(event)
    }

    private var isComposingText: Bool {
        (firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }
}
