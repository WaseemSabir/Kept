/// Whether Kept may post keyboard events, and how to get that permission.
/// `PasteService` depends on this rather than on CoreGraphics, so tests can
/// play granted, denied and first-time.
@MainActor
protocol PermissionChecking: AnyObject {
    /// `CGPreflightPostEventAccess()`: the TCC PostEvent permission, which
    /// System Settings lists under Privacy & Security.
    var canPostEvents: Bool { get }
    /// `CGRequestPostEventAccess()`: adds Kept to the list in System
    /// Settings and shows the system prompt (only the first time, ever).
    func requestAccess()
    /// Opens the Privacy & Security pane where the user turns it on.
    func openSettings()
}
