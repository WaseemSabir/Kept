import AppKit

/// The Settings window (and the welcome window). Kept is an agent app
/// without a main menu, so the window handles ⌘W and ⌘Q itself. (A
/// shortcut recorder that's recording sees keys first, so ⌘W can still be
/// recorded.)
final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let key = event.charactersIgnoringModifiers?.lowercased() {
            switch key {
            case "w":
                performClose(nil)
                return true
            case "q":
                NSApplication.shared.terminate(nil)
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
