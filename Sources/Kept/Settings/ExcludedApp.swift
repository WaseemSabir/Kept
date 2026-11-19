import Foundation

/// One row of the excluded apps list.
struct ExcludedApp: Identifiable, Equatable, Sendable {
    let bundleID: String
    /// The app's name; `nil` when it isn't installed.
    let name: String?

    var id: String { bundleID }

    /// What the row says: the name, or the bundle ID for an app that isn't
    /// installed.
    var title: String { name ?? bundleID }

    var isInstalled: Bool { name != nil }

    /// The bundle ID of the app bundle at `url` (from its Info.plist).
    static func bundleIdentifier(ofAppAt url: URL) -> String? {
        guard let identifier = Bundle(url: url)?.bundleIdentifier, !identifier.isEmpty else { return nil }
        return identifier
    }
}
