import AppKit

/// Whether macOS lets Kept read the clipboard on its own. From macOS 15.4
/// each app has a setting (`NSPasteboard.accessBehavior`) that users change
/// in System Settings › Privacy & Security › Paste from Other Apps. A
/// clipboard history reads on every copy, so anything but the system's
/// default or "Allow" leaves it unable to keep anything.
enum PasteboardAccess: Equatable, Sendable {
    /// Kept reads the clipboard as it always has: the system default, set
    /// to allow, or a macOS before 15.4.
    case allowed
    /// macOS asks the user each time Kept reads the clipboard.
    case asks
    /// macOS never lets Kept read the clipboard.
    case denied

    @available(macOS 15.4, *)
    init(_ behavior: NSPasteboard.AccessBehavior) {
        switch behavior {
        case .ask: self = .asks
        case .alwaysDeny: self = .denied
        case .default, .alwaysAllow: self = .allowed
        @unknown default: self = .allowed
        }
    }

    /// Whether to show `problem` and `direction` (welcome window, Settings).
    var needsAttention: Bool { self != .allowed }

    /// What's wrong, in one line; `nil` when nothing is.
    var problem: String? {
        needsAttention ? "Kept can't see what you copy until you allow it." : nil
    }

    /// Why, and where to change it. macOS 26 lists the setting as Paste
    /// from Other Apps; later versions may move it, so from 27 the copy
    /// names only Privacy & Security, which holds it either way.
    func direction(osMajorVersion: Int) -> String? {
        let setting = switch self {
        case .allowed: ""
        case .asks: "macOS is set to ask each time Kept reads the clipboard."
        case .denied: "macOS is set to deny Kept access to the clipboard."
        }
        guard needsAttention else { return nil }
        let place = osMajorVersion >= 27
            ? "In System Settings › Privacy & Security, look for Paste from Other Apps and choose Allow for Kept."
            : "In System Settings › Privacy & Security › Paste from Other Apps, choose Allow for Kept."
        return "\(setting) \(place)"
    }
}
