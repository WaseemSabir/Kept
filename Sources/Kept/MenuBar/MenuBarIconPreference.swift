import Foundation

/// Whether Kept's icon shows in the menu bar: the "Show Kept in the menu
/// bar" checkbox in Settings, which ⌘-dragging the icon out of the menu bar
/// also turns off. Kept writes it to UserDefaults (`showsMenuBarIcon`, on
/// unless set), where `StatusItemController` follows it; opening Kept again
/// turns it back on, so the icon can always be restored.
struct MenuBarIconPreference {
    static let key = "showsMenuBarIcon"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isShown: Bool {
        get { defaults.object(forKey: Self.key) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }
}
