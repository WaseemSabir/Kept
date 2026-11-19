import AppKit

/// `NSPasteboard.general.accessBehavior` where macOS has it (15.4+).
/// Reading it doesn't read the clipboard or prompt.
@MainActor
final class SystemPasteboardAccess: PasteboardAccessChecking {
    var access: PasteboardAccess {
        if #available(macOS 15.4, *) {
            return PasteboardAccess(NSPasteboard.general.accessBehavior)
        }
        return .allowed
    }

    func openSettings() {
        guard let url = PostEventPermission.privacySettingsURL, NSWorkspace.shared.open(url) else {
            Log.settings.error("Couldn't open Privacy & Security settings.")
            return
        }
    }
}
