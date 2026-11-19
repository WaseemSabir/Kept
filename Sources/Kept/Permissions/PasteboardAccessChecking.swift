/// Reads Kept's clipboard access, so Settings and the welcome window can be
/// tested in every state.
@MainActor
protocol PasteboardAccessChecking: AnyObject {
    var access: PasteboardAccess { get }
    /// Opens Privacy & Security in System Settings.
    func openSettings()
}
