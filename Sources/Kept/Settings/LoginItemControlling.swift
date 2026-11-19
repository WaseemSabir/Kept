/// Opening Kept at login. `SettingsModel` depends on this rather than on
/// ServiceManagement, so tests can play every status and failure.
@MainActor
protocol LoginItemControlling: AnyObject {
    /// Read fresh each time: the user can change it in System Settings.
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    /// Opens System Settings › General › Login Items.
    func openSystemSettings()
}
