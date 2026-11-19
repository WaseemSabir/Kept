import Foundation
import KeptCore

/// What the panel's views read: action titles, the empty state, previews,
/// facts and what VoiceOver says. Nothing here changes the model.
@MainActor
extension PanelViewModel {
    var isCapturePaused: Bool { capturePaused() }

    /// ⌘⌫ deletes the selected clip only while the search field is empty;
    /// with a query it deletes to the start of the line, as in any text
    /// field.
    var canDeleteWithKey: Bool { query.isEmpty && selectedClip != nil }

    /// The query's words, for marking matches in the rows.
    var matchTokens: [String] { MatchHighlighter.tokens(of: query) }

    /// Unpinned clips in the whole history, for the clear confirmation.
    var unpinnedCount: Int { store?.recent.count ?? 0 }

    /// "Clear 13 unpinned clips? Pinned clips stay."
    var clearConfirmationMessage: String {
        let count = unpinnedCount
        let clips = count == 1 ? "1 unpinned clip" : "\(count.formatted()) unpinned clips"
        return "Clear \(clips)? Pinned clips stay."
    }

    // MARK: Action titles

    /// What ⏎ does: "Paste", or "Copy" when pasting directly is off; "as
    /// plain text" when that's the default.
    var primaryActionTitle: String {
        let options = pasteOptions()
        let verb = options.pasteDirectly ? "Paste" : "Copy"
        return options.alwaysPastePlainText ? "\(verb) as plain text" : verb
    }

    /// What ⌥⏎ does: the other format.
    var alternateActionTitle: String {
        let options = pasteOptions()
        let verb = options.pasteDirectly ? "Paste" : "Copy"
        return options.alwaysPastePlainText ? "\(verb) with formatting" : "\(verb) as plain text"
    }

    /// What ⌘⏎ does, or `nil` when ⏎ already only copies.
    var copyOnlyActionTitle: String? {
        pasteOptions().pasteDirectly ? "Copy" : nil
    }

    /// What ⌘P does to the selected clip.
    var pinActionTitle: String { selectedClip.map { ClipMenu.pinTitle(for: $0) } ?? "Pin" }

    /// The row's context menu for `clip` (see `ClipMenu`).
    func menuSections(for clip: Clip) -> [[ClipMenu.Item]] {
        ClipMenu.sections(
            for: clip,
            primaryTitle: primaryActionTitle,
            alternateTitle: alternateActionTitle,
            copyOnlyTitle: copyOnlyActionTitle
        )
    }

    // MARK: The list

    /// Whether pins can be dragged or moved with ⌥⌘↑ / ⌥⌘↓ here: the list
    /// shows them in their own order, so a pin's row is its place.
    var canReorderPins: Bool {
        !isSearching && (filter == .all || filter == .pinned)
    }

    /// The row where unpinned clips start below the pinned section, when the
    /// list shows both (an empty query lists pins first).
    var sectionBreakIndex: Int? {
        guard !isSearching, filter != .pinned else { return nil }
        let pinCount = results.prefix { $0.isPinned }.count
        return pinCount > 0 && pinCount < results.count ? pinCount : nil
    }

    /// What to say when the list is empty; `nil` when it isn't.
    var emptyState: EmptyState? {
        guard results.isEmpty else { return nil }
        guard let store else {
            let reason = unavailableReason.map { "\($0) " } ?? ""
            return EmptyState(
                title: "Kept couldn't open your history.",
                hint: "\(reason)Quit and reopen Kept to try again.",
                spansPanel: true
            )
        }
        if store.pinned.isEmpty, store.recent.isEmpty {
            if isCapturePaused {
                return EmptyState(
                    title: "Capture is paused.",
                    hint: "Resume it from the Kept menu in the menu bar, then copy something.",
                    spansPanel: true
                )
            }
            return EmptyState(
                title: "Copy something and it shows up here.",
                hint: "Text, links, images and files you copy are kept here. Pin the ones you use often with ⌘P.",
                spansPanel: true
            )
        }
        if isSearching {
            let shownQuery = Self.shortened(query.trimmingCharacters(in: .whitespaces))
            return EmptyState(
                title: "No \(ClipDisplay.noun(for: filter)) match “\(shownQuery)”.",
                hint: filter == .all
                    ? "Press Esc to clear the search."
                    : "Press Esc to clear the search, or Tab to look in other kinds.",
                spansPanel: false
            )
        }
        switch filter {
        case .all:
            return EmptyState(title: "Nothing to show.", hint: nil, spansPanel: false)
        case .pinned:
            return EmptyState(
                title: "No pinned clips yet.",
                hint: "Select a clip and press ⌘P to keep it at the top.",
                spansPanel: false
            )
        case .text:
            return EmptyState(title: "No text clips yet.", hint: "Text you copy shows up here.", spansPanel: false)
        case .links:
            return EmptyState(title: "No links yet.", hint: "Links you copy show up here.", spansPanel: false)
        case .images:
            return EmptyState(
                title: "No images yet.",
                hint: "Copy an image, or press ⌃⇧⌘4 to copy part of the screen.",
                spansPanel: false
            )
        case .files:
            return EmptyState(title: "No files yet.", hint: "Copy files in Finder and they show up here.", spansPanel: false)
        }
    }

    private static func shortened(_ text: String, limit: Int = 40) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    // MARK: The preview

    /// The clip's preview: kept from before, or made now for a small clip;
    /// `.loading` while a big one still has to be read (`loadPreview(for:)`).
    func preview(for clip: Clip) -> ClipPreview {
        previews.preview(for: clip)
    }

    /// Reads a big clip's preview off the main actor; `nil` when the caller
    /// was cancelled (another clip was selected first).
    func loadPreview(for clip: Clip) async -> ClipPreview? {
        await previews.load(clip)
    }

    func facts(for clip: Clip, preview: ClipPreview) -> [ClipFact] {
        ClipFacts.facts(for: clip, preview: preview, appName: sourceAppName(of: clip), now: now)
    }

    // MARK: Accessibility

    /// The row's accessibility label (see `ClipAccessibility`).
    func accessibilityLabel(for clip: Clip) -> String {
        ClipAccessibility.label(for: clip, appName: sourceAppName(of: clip), now: now)
    }

    /// Tells VoiceOver which clip is selected now, since the search field
    /// keeps the keyboard focus: "Link, github.com/…, 9 minutes ago, from
    /// Safari. 4 of 15."
    func announceSelection() {
        guard let clip = selectedClip, let index = selectedIndex else {
            if let emptyState { announce(emptyState.title) }
            return
        }
        announce(ClipAccessibility.announcement(
            for: clip,
            position: index + 1,
            of: results.count,
            appName: sourceAppName(of: clip),
            now: Date()
        ))
    }

    /// The name of the app `clip` was copied from, when it's known and
    /// installed.
    private func sourceAppName(of clip: Clip) -> String? {
        guard let bundleID = clip.sourceBundleID else { return nil }
        return appName(bundleID)
    }
}
