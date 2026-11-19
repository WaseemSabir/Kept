/// How one paste is carried out, decided by `PastePolicy` before anything
/// is written.
struct PastePlan: Equatable, Sendable {
    /// The small HUD shown when Kept copied but didn't paste.
    enum Hint: Equatable, Sendable {
        /// "Copied. Press ⌘V to paste.", why Kept didn't paste, and a button
        /// that opens Privacy & Security settings. Shown once.
        case allowPasting
        /// "Copied. Press ⌘V to paste."
        case pressCommandV
    }

    /// Write only plain text (`true`) or every representation.
    var plainText: Bool
    /// Post ⌘V to the frontmost app once the panel is hidden.
    var postsPaste: Bool
    /// Ask macOS for the PostEvent permission (`CGRequestPostEventAccess`),
    /// which shows its prompt.
    var requestsAccess = false
    var hint: Hint?

    /// Paste: write, then post ⌘V.
    static func paste(plainText: Bool) -> PastePlan {
        PastePlan(plainText: plainText, postsPaste: true)
    }

    /// Only write; the user pastes.
    static func copy(plainText: Bool, hint: Hint? = nil, requestsAccess: Bool = false) -> PastePlan {
        PastePlan(plainText: plainText, postsPaste: false, requestsAccess: requestsAccess, hint: hint)
    }
}
