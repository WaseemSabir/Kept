/// The Settings window's panes, in toolbar order.
enum SettingsPane: String, CaseIterable, Sendable {
    case general
    case shortcuts
    case privacy
    case about

    /// The toolbar label, which is also the window title.
    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .privacy: "Privacy"
        case .about: "About"
        }
    }

    /// The SF Symbol above the label.
    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "command"
        case .privacy: "hand.raised"
        case .about: "info.circle"
        }
    }
}
