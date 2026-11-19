import CoreGraphics
import KeptCore

/// Puts a clip back where the user is typing. The panel depends on this
/// rather than on `PasteService`, so its logic can be tested without a
/// pasteboard or synthesized key presses.
///
/// Pasting has two steps because the panel must be gone before ⌘V is
/// posted, but must stay open (to say so) if the clip can't be written.
///
/// A big clip pasted as plain text has its text worked out off the main
/// actor first: `startLoading(_:for:)` returns the task to wait for, and
/// `prepare(_:for:)` then writes what it read.
@MainActor
protocol ClipPasting: AnyObject {
    /// Starts reading, off the main actor, what pasting `clip` for `request`
    /// writes, when doing that on the main actor would hold it up. `nil`
    /// when there's nothing slow to do, and `prepare(_:for:)` can run at once.
    func startLoading(_ clip: Clip, for request: PasteRequest) -> Task<Void, Never>?

    /// Decides how `request` is carried out, writes `clip` to the pasteboard
    /// in that format and moves it to the top of the history. Throws when
    /// the clip can't be written; nothing else happens then.
    func prepare(_ clip: Clip, for request: PasteRequest) throws -> PastePlan

    /// Finishes `plan` once the panel is hidden: posts ⌘V, or asks for
    /// access and shows a hint near `anchor` (where the panel was).
    func complete(_ plan: PastePlan, anchor: CGRect?)
}

extension ClipPasting {
    func startLoading(_ clip: Clip, for request: PasteRequest) -> Task<Void, Never>? {
        nil
    }
}
