/// Where a posted ⌘V would go. `PasteService` depends on this rather than
/// on AppKit and Carbon, so tests can play each case.
@MainActor
protocol KeyboardFocusChecking: AnyObject {
    /// Kept is the active app (its Settings window, say), so ⌘V would paste
    /// into Kept. The panel itself never activates Kept.
    var isKeptFrontmost: Bool { get }
    /// Some app has secure event input on (a password field, Terminal's
    /// Secure Keyboard Entry); a posted ⌘V is then likely dropped.
    var isSecureInputEnabled: Bool { get }
}
