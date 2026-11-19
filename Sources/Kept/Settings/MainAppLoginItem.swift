import ServiceManagement

/// Kept itself as a login item (`SMAppService.mainApp`), registered with
/// launchd rather than a helper app.
@MainActor
final class MainAppLoginItem: LoginItemControlling {
    var status: LoginItemStatus {
        LoginItemStatus(SMAppService.mainApp.status)
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

extension LoginItemStatus {
    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notRegistered: self = .notRegistered
        case .notFound: self = .notFound
        @unknown default: self = .notFound
        }
    }
}
