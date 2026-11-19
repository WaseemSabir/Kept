import CoreGraphics
import KeptCore

/// Puts a clip back where the user is typing. The panel depends on this
/// rather than on `PasteService`, so its logic can be tested without a
/// pasteboard or synthesized key presses.
///
/// Pasting has two steps because the panel must be gone before ⌘V is
/// posted, but must stay open (to say so) if the clip can't be written.
@MainActor
protocol ClipPasting: AnyObject {
    /// Decides how `request` is carried out, writes `clip` to the pasteboard
    /// in that format and moves it to the top of the history. Throws when
    /// the clip can't be written; nothing else happens then.
    func prepare(_ clip: Clip, for request: PasteRequest) throws -> PastePlan

    /// Finishes `plan` once the panel is hidden: posts ⌘V, or asks for
    /// access and shows a hint near `anchor` (where the panel was).
    func complete(_ plan: PastePlan, anchor: CGRect?)
}
