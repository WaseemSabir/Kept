import AppKit
import Carbon

/// The live answers for `KeyboardFocusChecking`.
@MainActor
final class SystemKeyboardFocus: KeyboardFocusChecking {
    var isKeptFrontmost: Bool {
        NSRunningApplication.current.isActive
    }

    var isSecureInputEnabled: Bool {
        IsSecureEventInputEnabled()
    }
}
