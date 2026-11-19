import KeptCore

/// The paste preferences, as a plain value for `PastePolicy` and the
/// panel's footer (`Preferences.pasteOptions` in the app).
struct PasteOptions: Equatable, Sendable {
    /// Post ⌘V after writing (`true`), or only copy (`false`).
    var pasteDirectly = PreferenceDefaults.pasteDirectly
    /// ⏎ pastes plain text and ⌥⏎ pastes with formatting, instead of the
    /// other way around.
    var alwaysPastePlainText = PreferenceDefaults.alwaysPastePlainText
}

extension Preferences {
    var pasteOptions: PasteOptions {
        PasteOptions(pasteDirectly: pasteDirectly, alwaysPastePlainText: alwaysPastePlainText)
    }
}
