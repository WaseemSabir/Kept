/// Decides how a paste is carried out: which format to write, whether to
/// post ⌘V, whether to ask for the PostEvent permission and which hint to
/// show. Pure, so every combination is unit-tested.
///
/// In order:
/// 1. ⌘⏎, or "paste directly" turned off: copy only, quietly; the user
///    chose that.
/// 2. Kept itself is frontmost (its Settings window, say): ⌘V would land
///    in Kept, so copy and say "Press ⌘V".
/// 3. No PostEvent access: copy, ask macOS once, and explain once with a
///    button to allow it; after that only "Press ⌘V".
/// 4. Secure input is on (a password field somewhere): a posted ⌘V is
///    likely dropped without a trace, so copy and say "Press ⌘V".
/// 5. Otherwise paste.
enum PastePolicy {
    /// What the system and Kept's own memory say right now.
    struct Conditions: Equatable, Sendable {
        /// `CGPreflightPostEventAccess()`.
        var canPostEvents = true
        /// Kept has called `CGRequestPostEventAccess()` before (persisted).
        var hasRequestedAccess = false
        /// The hint with the "Allow Kept to paste…" button has been shown
        /// before (persisted).
        var hasShownPermissionHint = false
        /// Kept is the active app, so a posted ⌘V would go to Kept.
        var isKeptFrontmost = false
        /// `IsSecureEventInputEnabled()`.
        var isSecureInputEnabled = false
    }

    static func plan(for request: PasteRequest, options: PasteOptions, conditions: Conditions) -> PastePlan {
        let plainText = writesPlainText(request, options: options)
        if request == .copyOnly || !options.pasteDirectly {
            return .copy(plainText: plainText)
        }
        if conditions.isKeptFrontmost {
            return .copy(plainText: plainText, hint: .pressCommandV)
        }
        if !conditions.canPostEvents {
            return .copy(
                plainText: plainText,
                hint: conditions.hasShownPermissionHint ? .pressCommandV : .allowPasting,
                requestsAccess: !conditions.hasRequestedAccess
            )
        }
        if conditions.isSecureInputEnabled {
            return .copy(plainText: plainText, hint: .pressCommandV)
        }
        return .paste(plainText: plainText)
    }

    /// ⏎ writes the clip as copied and ⌥⏎ plain text; "always paste plain
    /// text" swaps them. ⌘⏎ writes what ⏎ would.
    static func writesPlainText(_ request: PasteRequest, options: PasteOptions) -> Bool {
        switch request {
        case .paste(let alternate): options.alwaysPastePlainText != alternate
        case .copyOnly: options.alwaysPastePlainText
        case .clipboardAsPlainText: true
        }
    }
}
