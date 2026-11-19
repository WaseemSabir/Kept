/// Posts the paste shortcut to the frontmost app. `PasteService` depends
/// on this rather than on `CGEvent`, so tests can count pastes.
@MainActor
protocol KeystrokePosting: AnyObject {
    /// Posts ⌘V (the key that types "v" in the current layout) to whatever
    /// app is frontmost, shortly after the call returns, once the panel is
    /// out of the way.
    func postPasteShortcut()
}
