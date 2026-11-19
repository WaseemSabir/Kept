import CoreGraphics

/// Shows the copy-only hint. `PasteService` depends on this rather than on
/// the HUD window, so tests can record hints.
@MainActor
protocol PasteHintPresenting: AnyObject {
    /// Shows `hint` near `anchor` (the panel's frame, in screen
    /// coordinates), or at the bottom of the active screen when it's `nil`.
    func show(_ hint: PastePlan.Hint, anchor: CGRect?)
}
