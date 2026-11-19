import AppKit
import KeptCore

/// Puts clips back where the user is typing.
///
/// `prepare` asks `PastePolicy` how (the format, paste or copy only) and
/// writes the clip, telling the monitor the change count so the write is
/// never captured as a new copy. Once the panel is hidden, `complete` posts
/// ⌘V, or asks for the PostEvent permission and shows a hint.
@MainActor
final class PasteService: ClipPasting {
    enum Failure: Error, CustomStringConvertible {
        /// The pasteboard refused the write.
        case pasteboardRejected

        var description: String {
            switch self {
            case .pasteboardRejected: "The pasteboard didn't accept the clip."
            }
        }
    }

    private let store: HistoryStore
    private let writer: PasteboardWriter
    private let monitor: PasteboardMonitor
    private let options: @MainActor () -> PasteOptions
    private let permission: any PermissionChecking
    private let poster: any KeystrokePosting
    private let focus: any KeyboardFocusChecking
    private let onboarding: PasteOnboarding
    private let hints: any PasteHintPresenting

    init(
        store: HistoryStore,
        writer: PasteboardWriter,
        monitor: PasteboardMonitor,
        options: @escaping @MainActor () -> PasteOptions,
        permission: any PermissionChecking,
        poster: any KeystrokePosting,
        focus: any KeyboardFocusChecking,
        onboarding: PasteOnboarding,
        hints: any PasteHintPresenting
    ) {
        self.store = store
        self.writer = writer
        self.monitor = monitor
        self.options = options
        self.permission = permission
        self.poster = poster
        self.focus = focus
        self.onboarding = onboarding
        self.hints = hints
    }

    // MARK: ClipPasting

    func prepare(_ clip: Clip, for request: PasteRequest) throws -> PastePlan {
        let plan = plan(for: request)
        let items = try store.representations(for: clip.id)
        try write(
            PasteboardWriter.payload(of: items, plainTextOnly: plan.plainText),
            sourceBundleID: clip.sourceBundleID
        )
        try store.markUsed(clip.id)
        return plan
    }

    func complete(_ plan: PastePlan, anchor: CGRect?) {
        if plan.requestsAccess {
            onboarding.hasRequestedAccess = true
            permission.requestAccess()
        }
        if plan.postsPaste {
            poster.postPasteShortcut()
        }
        if let hint = plan.hint {
            if hint == .allowPasting { onboarding.hasShownPermissionHint = true }
            hints.show(hint, anchor: anchor)
        }
    }

    // MARK: Paste clipboard as plain text

    /// The global shortcut: replaces what's on the pasteboard with its plain
    /// text and pastes it, by the same rules as the panel (copy only and a
    /// hint when Kept can't paste). Returns `nil`, changing nothing, when
    /// the pasteboard holds no text or the write fails.
    @discardableResult
    func pasteClipboardAsPlainText() -> PastePlan? {
        // A copy made in the last half second hasn't been polled yet; record
        // it before it's replaced.
        monitor.poll()
        guard let conversion = ClipboardPlainText.read(from: writer.pasteboard) else { return nil }
        let plan = plan(for: .clipboardAsPlainText)
        do {
            try write(conversion.items, sourceBundleID: conversion.sourceBundleID, markers: conversion.markers)
        } catch {
            Log.paste.error("Couldn't write the clipboard as plain text: \(String(describing: error), privacy: .public)")
            return nil
        }
        complete(plan, anchor: nil)
        return plan
    }

    // MARK: Helpers

    /// What `PastePolicy` decides for `request` right now.
    func plan(for request: PasteRequest) -> PastePlan {
        PastePolicy.plan(
            for: request,
            options: options(),
            conditions: PastePolicy.Conditions(
                canPostEvents: permission.canPostEvents,
                hasRequestedAccess: onboarding.hasRequestedAccess,
                hasShownPermissionHint: onboarding.hasShownPermissionHint,
                isKeptFrontmost: focus.isKeptFrontmost,
                isSecureInputEnabled: focus.isSecureInputEnabled
            )
        )
    }

    private func write(_ items: [PasteboardItem], sourceBundleID: String?, markers: [PasteboardType] = []) throws {
        guard let changeCount = writer.write(items, sourceBundleID: sourceBundleID, markers: markers) else {
            throw Failure.pasteboardRejected
        }
        monitor.noteOwnWrite(changeCount: changeCount)
    }
}
