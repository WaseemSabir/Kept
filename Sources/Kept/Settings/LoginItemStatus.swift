/// Kept's login item, as `SMAppService.mainApp.status` reports it.
enum LoginItemStatus: Equatable, Sendable {
    /// Kept opens at login.
    case enabled
    /// Registered, but the user has to allow it in System Settings ›
    /// General › Login Items.
    case requiresApproval
    case notRegistered
    /// macOS couldn't find the service; reported for some unsigned builds.
    case notFound
}
