/// Where the keyboard goes when one of Kept's windows (Settings, the
/// welcome window) closes. Kept is an agent app: left active with no window
/// it would swallow keystrokes, and the panel would only ever copy, since a
/// paste needs another app in front.
enum FocusReturn: Equatable, Sendable {
    /// Leave things as they are: Kept isn't active, or another of its
    /// windows is still open and needs the keyboard.
    case stay
    /// Activate the app with this process ID: the last one the user was in,
    /// even if they switched to it while the window was open.
    case activate(processID: Int32)
    /// No app to go back to: hide Kept, so the next app in line becomes
    /// active.
    case hide

    /// - Parameters:
    ///   - isKeptActive: `NSApplication.isActive`.
    ///   - otherWindowIsOpen: another titled Kept window stays open.
    ///   - lastOtherApp: the last app other than Kept that was active and
    ///     is still running, by process ID.
    static func choice(isKeptActive: Bool, otherWindowIsOpen: Bool, lastOtherApp: Int32?) -> FocusReturn {
        guard isKeptActive, !otherWindowIsOpen else { return .stay }
        guard let lastOtherApp else { return .hide }
        return .activate(processID: lastOtherApp)
    }
}
