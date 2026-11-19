import Foundation

/// What Kept remembers about asking for the paste permission, so it asks
/// macOS once and explains once, never on every paste.
///
/// Stored in `UserDefaults` beside the preferences (keys in `Key`); not a
/// setting the user changes, so it lives in the app rather than in
/// `KeptCore.Preferences`.
@MainActor
final class PasteOnboarding {
    enum Key {
        static let requestedAccess = "pasteAccessRequested"
        static let shownPermissionHint = "pastePermissionHintShown"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Kept has called `CGRequestPostEventAccess()`, which shows the system
    /// prompt.
    var hasRequestedAccess: Bool {
        get { defaults.bool(forKey: Key.requestedAccess) }
        set { defaults.set(newValue, forKey: Key.requestedAccess) }
    }

    /// The hint with the "Allow Kept to paste…" button has been shown; later
    /// copy-only pastes say only "Press ⌘V to paste."
    var hasShownPermissionHint: Bool {
        get { defaults.bool(forKey: Key.shownPermissionHint) }
        set { defaults.set(newValue, forKey: Key.shownPermissionHint) }
    }
}
