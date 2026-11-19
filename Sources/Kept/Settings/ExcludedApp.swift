import Foundation

/// One row of the excluded apps list.
struct ExcludedApp: Identifiable, Equatable, Sendable {
    let bundleID: String
    /// The app's name; `nil` when it isn't installed.
    let name: String?

    var id: String { bundleID }

    /// What the row says: the name, a known name for the password managers
    /// Kept excludes from the start, or the bundle ID for any other app
    /// that isn't installed.
    var title: String { name ?? Self.knownName(for: bundleID) ?? bundleID }

    var isInstalled: Bool { name != nil }

    /// Names for the apps on the default list, so a missing one still reads
    /// "1Password" rather than "com.1password.1password". Bundle IDs
    /// compare without regard to case, as capture compares them.
    static func knownName(for bundleID: String) -> String? {
        knownNames[bundleID.lowercased()]
    }

    private static let knownNames: [String: String] = [
        "com.1password.1password": "1Password",
        "com.agilebits.onepassword7": "1Password 7",
        "com.bitwarden.desktop": "Bitwarden",
        "org.keepassxc.keepassxc": "KeePassXC",
        "com.apple.passwords": "Passwords",
        "com.apple.keychainaccess": "Keychain Access",
    ]

    /// The bundle ID of the app bundle at `url` (from its Info.plist).
    static func bundleIdentifier(ofAppAt url: URL) -> String? {
        guard let identifier = Bundle(url: url)?.bundleIdentifier, !identifier.isEmpty else { return nil }
        return identifier
    }
}
