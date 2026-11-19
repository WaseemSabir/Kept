import Carbon
import Foundation

/// The key that types "v" in the current keyboard layout, for posting ⌘V.
///
/// Resolved with `PasteKeyResolver` from the current layout and the current
/// ASCII-capable layout, cached, and forgotten whenever the user switches
/// input sources (the next paste resolves it again).
@MainActor
final class KeyboardLayout {
    private static let inputSourceDidChange = Notification.Name(
        kTISNotifySelectedKeyboardInputSourceChanged as String
    )

    private var cachedPasteKeyCode: CGKeyCode?
    // Kept for the app's lifetime, like the layout itself.
    private var observer: (any NSObjectProtocol)?

    init() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.inputSourceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cachedPasteKeyCode = nil
            }
        }
    }

    /// The virtual key code to post with ⌘ for a paste.
    var pasteKeyCode: CGKeyCode {
        if let cachedPasteKeyCode { return cachedPasteKeyCode }
        let keyCode = PasteKeyResolver.keyCode(typing: "v", in: Self.currentLayouts())
        cachedPasteKeyCode = keyCode
        return keyCode
    }

    /// The current layout, then the current ASCII-capable one.
    private static func currentLayouts() -> [any KeyTranslating] {
        let keyboardType = UInt32(LMGetKbdType())
        let sources = [
            TISCopyCurrentKeyboardLayoutInputSource(),
            TISCopyCurrentASCIICapableKeyboardLayoutInputSource(),
        ]
        return sources.compactMap { unmanaged -> (any KeyTranslating)? in
            guard let source = unmanaged?.takeRetainedValue() else { return nil }
            return UnicodeKeyLayout(source: source, keyboardType: keyboardType)
        }
    }
}
