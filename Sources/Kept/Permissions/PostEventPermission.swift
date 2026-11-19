import AppKit
import CoreGraphics

/// The TCC PostEvent permission, which synthesized ⌘V needs.
///
/// PostEvent (unlike full Accessibility, `AXIsProcessTrusted`) works in the
/// App Sandbox. Up to macOS 26, System Settings lists it under Privacy &
/// Security › Accessibility. macOS 27 renamed that pane and 27.3 splits it,
/// and which part PostEvent lands in isn't confirmed (docs/RESEARCH.md §5),
/// so the Accessibility anchor is tried first and Privacy & Security itself
/// is the fallback.
@MainActor
final class PostEventPermission: PermissionChecking {
    static let accessibilitySettingsURL =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security")

    var canPostEvents: Bool {
        CGPreflightPostEventAccess()
    }

    func requestAccess() {
        _ = CGRequestPostEventAccess()
    }

    func openSettings() {
        for url in [Self.accessibilitySettingsURL, Self.privacySettingsURL].compactMap({ $0 }) {
            if NSWorkspace.shared.open(url) { return }
        }
        Log.paste.error("Couldn't open Privacy & Security settings.")
    }
}
