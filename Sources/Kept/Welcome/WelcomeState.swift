import Foundation

/// Whether the welcome window has opened (UserDefaults `welcomeShown`). It
/// opens by itself once, at the first launch; About opens it again.
struct WelcomeState {
    static let key = "welcomeShown"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasBeenShown: Bool {
        get { defaults.bool(forKey: Self.key) }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }

    /// Only the first launch shows the window by itself.
    var shouldShowAtLaunch: Bool { !hasBeenShown }
}
