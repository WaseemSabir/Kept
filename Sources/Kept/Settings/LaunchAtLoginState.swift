/// What the "Open Kept at login" checkbox shows: whether it's on, a note
/// under it, and whether to offer a button to Login Items settings.
///
/// Comes from the login item's status (read each time) and whatever went
/// wrong the last time the user changed it.
struct LaunchAtLoginState: Equatable, Sendable {
    enum Failure: Equatable, Sendable {
        case couldNotRegister
        case couldNotUnregister
    }

    var isOn: Bool
    var note: String?
    var offersLoginItemsSettings: Bool

    init(status: LoginItemStatus, failure: Failure?) {
        isOn = status == .enabled || status == .requiresApproval
        switch failure {
        case .couldNotRegister:
            note = "Kept couldn't add itself to your login items. Builds without a Developer ID signature often can't; you can add Kept in Login Items settings instead."
            offersLoginItemsSettings = true
        case .couldNotUnregister:
            note = "Kept couldn't remove itself from your login items. You can remove it in Login Items settings."
            offersLoginItemsSettings = true
        case nil where status == .requiresApproval:
            note = "Allow Kept in Login Items settings to finish turning this on."
            offersLoginItemsSettings = true
        case nil:
            note = nil
            offersLoginItemsSettings = false
        }
    }
}
