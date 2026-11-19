import KeptCore

/// Puts a clip back on the pasteboard. The panel depends on this rather than
/// on `PasteService`, so its logic can be tested without a pasteboard.
@MainActor
protocol ClipCopying: AnyObject {
    /// Writes `clip` to the pasteboard (all representations, or plain text
    /// only) and moves it to the top of the history.
    func copy(_ clip: Clip, asPlainText: Bool) throws
}
