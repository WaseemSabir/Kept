import Testing
@testable import Kept

@Suite("Paste policy")
struct PastePolicyTests {
    /// The permission as a paste finds it.
    enum Access: CaseIterable, CustomStringConvertible {
        case granted
        /// Never asked: the first paste asks.
        case firstTime
        /// Asked before and still missing.
        case denied

        var description: String {
            switch self {
            case .granted: "granted"
            case .firstTime: "first time"
            case .denied: "denied"
            }
        }
    }

    /// The keys (and the global shortcut) that put something back.
    enum Trigger: CaseIterable, CustomStringConvertible {
        case returnKey, optionReturn, commandReturn, commandDigit, optionCommandDigit, doubleClick, plainTextShortcut

        var request: PasteRequest {
            switch self {
            case .returnKey, .commandDigit, .doubleClick: .paste(alternate: false)
            case .optionReturn, .optionCommandDigit: .paste(alternate: true)
            case .commandReturn: .copyOnly
            case .plainTextShortcut: .clipboardAsPlainText
            }
        }

        var description: String {
            switch self {
            case .returnKey: "⏎"
            case .optionReturn: "⌥⏎"
            case .commandReturn: "⌘⏎"
            case .commandDigit: "⌘N"
            case .optionCommandDigit: "⌥⌘N"
            case .doubleClick: "double-click"
            case .plainTextShortcut: "plain-text shortcut"
            }
        }
    }

    private struct Case: CustomStringConvertible {
        let access: Access
        let hasShownPermissionHint: Bool
        let pasteDirectly: Bool
        let alwaysPastePlainText: Bool
        let trigger: Trigger
        let isKeptFrontmost: Bool
        let isSecureInputEnabled: Bool

        var options: PasteOptions {
            PasteOptions(pasteDirectly: pasteDirectly, alwaysPastePlainText: alwaysPastePlainText)
        }

        var conditions: PastePolicy.Conditions {
            PastePolicy.Conditions(
                canPostEvents: access == .granted,
                hasRequestedAccess: access == .denied,
                hasShownPermissionHint: hasShownPermissionHint,
                isKeptFrontmost: isKeptFrontmost,
                isSecureInputEnabled: isSecureInputEnabled
            )
        }

        var description: String {
            "access \(access), hint shown \(hasShownPermissionHint), paste directly \(pasteDirectly), "
                + "always plain \(alwaysPastePlainText), \(trigger), Kept frontmost \(isKeptFrontmost), "
                + "secure input \(isSecureInputEnabled)"
        }
    }

    private static let allCases: [Case] = {
        var cases: [Case] = []
        for access in Access.allCases {
            for hasShownPermissionHint in [false, true] {
                for pasteDirectly in [false, true] {
                    for alwaysPastePlainText in [false, true] {
                        for trigger in Trigger.allCases {
                            for isKeptFrontmost in [false, true] {
                                for isSecureInputEnabled in [false, true] {
                                    cases.append(Case(
                                        access: access,
                                        hasShownPermissionHint: hasShownPermissionHint,
                                        pasteDirectly: pasteDirectly,
                                        alwaysPastePlainText: alwaysPastePlainText,
                                        trigger: trigger,
                                        isKeptFrontmost: isKeptFrontmost,
                                        isSecureInputEnabled: isSecureInputEnabled
                                    ))
                                }
                            }
                        }
                    }
                }
            }
        }
        return cases
    }()

    /// The rules from the spec, written as a table of outcomes rather than
    /// in `PastePolicy`'s order.
    private static func expected(_ c: Case) -> PastePlan {
        let plainText: Bool = switch c.trigger {
        case .returnKey, .commandReturn, .commandDigit, .doubleClick: c.alwaysPastePlainText
        case .optionReturn, .optionCommandDigit: !c.alwaysPastePlainText
        case .plainTextShortcut: true
        }
        let wantsPaste = c.trigger != .commandReturn && c.pasteDirectly
        guard wantsPaste else { return PastePlan(plainText: plainText, postsPaste: false) }

        let canPaste = c.access == .granted && !c.isKeptFrontmost && !c.isSecureInputEnabled
        if canPaste { return PastePlan(plainText: plainText, postsPaste: true) }

        // Only a missing permission explains itself, asks macOS and offers
        // the button, and only when nothing else (Kept frontmost) stands in
        // the way first.
        let permissionIsTheProblem = c.access != .granted && !c.isKeptFrontmost
        return PastePlan(
            plainText: plainText,
            postsPaste: false,
            requestsAccess: permissionIsTheProblem && c.access == .firstTime,
            hint: permissionIsTheProblem && !c.hasShownPermissionHint ? .allowPasting : .pressCommandV
        )
    }

    @Test("Every combination of permission, preferences, key, focus and secure input")
    func matrix() {
        #expect(Self.allCases.count == 3 * 2 * 2 * 2 * 7 * 2 * 2)
        for c in Self.allCases {
            let plan = PastePolicy.plan(for: c.trigger.request, options: c.options, conditions: c.conditions)
            #expect(plan == Self.expected(c), "\(c)")
        }
    }

    @Test("Invariants hold across the matrix")
    func invariants() {
        for c in Self.allCases {
            let plan = PastePolicy.plan(for: c.trigger.request, options: c.options, conditions: c.conditions)
            // ⌘⏎ and copy-only mode never paste, ask or hint.
            if c.trigger == .commandReturn || !c.pasteDirectly {
                #expect(!plan.postsPaste && !plan.requestsAccess && plan.hint == nil, "\(c)")
            }
            // A paste is posted only when it can land, and then there's no hint.
            if plan.postsPaste {
                #expect(c.access == .granted && !c.isKeptFrontmost && !c.isSecureInputEnabled, "\(c)")
                #expect(plan.hint == nil && !plan.requestsAccess, "\(c)")
            } else if c.trigger != .commandReturn, c.pasteDirectly {
                // Every paste that became a copy says so.
                #expect(plan.hint != nil, "\(c)")
            }
            // macOS is asked at most once.
            if plan.requestsAccess { #expect(c.access == .firstTime, "\(c)") }
            // The long hint appears only until it has been shown once.
            if plan.hint == .allowPasting { #expect(!c.hasShownPermissionHint && c.access != .granted, "\(c)") }
        }
    }

    @Test("A first paste without permission copies, asks once and explains")
    func firstPasteWithoutPermission() {
        let plan = PastePolicy.plan(
            for: .paste(alternate: false),
            options: PasteOptions(),
            conditions: PastePolicy.Conditions(canPostEvents: false)
        )
        #expect(plan == PastePlan(plainText: false, postsPaste: false, requestsAccess: true, hint: .allowPasting))

        let later = PastePolicy.plan(
            for: .paste(alternate: false),
            options: PasteOptions(),
            conditions: PastePolicy.Conditions(canPostEvents: false, hasRequestedAccess: true, hasShownPermissionHint: true)
        )
        #expect(later == PastePlan(plainText: false, postsPaste: false, requestsAccess: false, hint: .pressCommandV))
    }

    @Test("Always paste plain text swaps ⏎ and ⌥⏎; ⌘⏎ follows ⏎; the shortcut is always plain")
    func formats() {
        let normal = PasteOptions()
        let plain = PasteOptions(alwaysPastePlainText: true)
        #expect(!PastePolicy.writesPlainText(.paste(alternate: false), options: normal))
        #expect(PastePolicy.writesPlainText(.paste(alternate: true), options: normal))
        #expect(!PastePolicy.writesPlainText(.copyOnly, options: normal))
        #expect(PastePolicy.writesPlainText(.paste(alternate: false), options: plain))
        #expect(!PastePolicy.writesPlainText(.paste(alternate: true), options: plain))
        #expect(PastePolicy.writesPlainText(.copyOnly, options: plain))
        #expect(PastePolicy.writesPlainText(.clipboardAsPlainText, options: normal))
        #expect(PastePolicy.writesPlainText(.clipboardAsPlainText, options: plain))
    }
}
