import Foundation
import KeptCore
import Observation

/// The panel's state and behavior: the query and type filter, the visible
/// clips (from `ClipSearch`), the selection, and every action the keyboard
/// or mouse can take. Views render it; `PanelKeyRouter` feeds it commands.
@MainActor
@Observable
final class PanelViewModel {
    enum SelectionPolicy {
        /// Select the first result (after the query or filter changed).
        case first
        /// Keep the selected clip; if it's gone, select whatever took its place.
        case keep
    }

    /// The search text. Changing it selects the best match.
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            isConfirmingClear = false
            refresh(selecting: .first)
        }
    }

    /// The type filter. Changing it selects the first result.
    var filter: ClipFilter = .all {
        didSet {
            guard filter != oldValue else { return }
            refresh(selecting: .first)
        }
    }

    /// The clips the list shows, best first.
    private(set) var results: [Clip] = []
    private(set) var selectedID: UUID?
    /// Whether the inline "clear unpinned clips?" bar is showing.
    private(set) var isConfirmingClear = false
    /// A short message about something that went wrong, shown in the footer.
    private(set) var notice: String?
    /// Goes up each time the panel opens, so views can refocus and scroll.
    private(set) var presentationCount = 0
    /// The time ages are measured from; updated when the panel opens.
    private(set) var now = Date()

    /// `nil` when the history couldn't be opened.
    let store: HistoryStore?
    /// Why the history couldn't be opened.
    let unavailableReason: String?

    /// Closes the panel.
    @ObservationIgnored var onDismiss: @MainActor () -> Void = {}
    /// Rows a PgUp / PgDn moves.
    @ObservationIgnored var pageSize = 10

    private let copier: (any ClipCopying)?
    private let appName: @MainActor (String) -> String?
    private let capturePaused: @MainActor () -> Bool
    @ObservationIgnored private var cachedPreview: (key: PreviewKey, preview: ClipPreview)?

    private struct PreviewKey: Equatable {
        let id: UUID
        let lastCopiedAt: Date
        let copyCount: Int
    }

    init(
        store: HistoryStore?,
        unavailableReason: String? = nil,
        copier: (any ClipCopying)? = nil,
        appName: @escaping @MainActor (String) -> String? = { _ in nil },
        capturePaused: @escaping @MainActor () -> Bool = { false }
    ) {
        self.store = store
        self.unavailableReason = unavailableReason
        self.copier = copier
        self.appName = appName
        self.capturePaused = capturePaused
        refresh(selecting: .first)
        observeHistory()
    }

    // MARK: Derived state

    var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return results.firstIndex { $0.id == selectedID }
    }

    var selectedClip: Clip? {
        selectedIndex.map { results[$0] }
    }

    var isCapturePaused: Bool { capturePaused() }

    var isSearching: Bool { !query.allSatisfy(\.isWhitespace) }

    /// Unpinned clips in the whole history, for the clear confirmation.
    var unpinnedCount: Int { store?.recent.count ?? 0 }

    /// What ⏎ does. Copy for now; pasting into the previous app comes next.
    var primaryActionTitle: String { "Copy" }
    var plainTextActionTitle: String { "Copy as plain text" }
    var pinActionTitle: String { selectedClip?.isPinned == true ? "Unpin" : "Pin" }

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

    /// The selected clip's preview, loaded once per selection.
    func preview(for clip: Clip) -> ClipPreview {
        let key = PreviewKey(id: clip.id, lastCopiedAt: clip.lastCopiedAt, copyCount: clip.copyCount)
        if let cachedPreview, cachedPreview.key == key { return cachedPreview.preview }
        let preview = PreviewLoader.preview(of: clip, store: store)
        cachedPreview = (key, preview)
        return preview
    }

    func facts(for clip: Clip, preview: ClipPreview) -> [ClipFact] {
        var name: String?
        if let bundleID = clip.sourceBundleID { name = appName(bundleID) }
        return ClipFacts.facts(for: clip, preview: preview, appName: name, now: now)
    }

    // MARK: Intents

    /// Resets the panel for a fresh look: empty query, all clips, first row.
    func prepareForShow() {
        isConfirmingClear = false
        notice = nil
        now = Date()
        query = ""
        filter = .all
        refresh(selecting: .first)
        presentationCount += 1
    }

    /// Carries out `command`. Returns `false` for commands the panel doesn't
    /// handle itself (text editing), so the key goes on to the search field.
    @discardableResult
    func perform(_ command: PanelCommand) -> Bool {
        if case .edit = command { return false }
        if isConfirmingClear {
            // ⏎ confirms; any other command (Esc included) backs out.
            if command == .activate(plainText: false) {
                confirmClearUnpinned()
            } else {
                isConfirmingClear = false
            }
            return true
        }

        notice = nil
        switch command {
        case .moveSelection(let offset):
            moveSelection(by: offset)
        case .movePage(let pages):
            moveSelection(by: pages * max(1, pageSize))
        case .selectFirst:
            select(index: 0)
        case .selectLast:
            select(index: results.count - 1)
        case .activate(let plainText):
            copy(selectedClip, plainText: plainText)
        case .copyOnly:
            copy(selectedClip, plainText: false)
        case .activateRow(let row, let plainText):
            if results.indices.contains(row) { copy(results[row], plainText: plainText) }
        case .togglePin:
            togglePin()
        case .delete:
            deleteSelection()
        case .requestClearUnpinned:
            requestClearUnpinned()
        case .clearQuery:
            query = ""
        case .cancel:
            if query.isEmpty { onDismiss() } else { query = "" }
        case .nextFilter:
            cycleFilter(by: 1)
        case .previousFilter:
            cycleFilter(by: -1)
        case .edit:
            return false
        }
        return true
    }

    /// Selects the row at `index`, clamped to the list.
    func select(index: Int) {
        guard !results.isEmpty else {
            selectedID = nil
            return
        }
        selectedID = results[min(max(index, 0), results.count - 1)].id
    }

    /// Selects `clip` (a click).
    func select(_ clip: Clip) {
        notice = nil
        isConfirmingClear = false
        selectedID = clip.id
    }

    /// Selects `clip` and puts it back, like ⏎ (a double-click).
    func activate(_ clip: Clip) {
        select(clip)
        copy(clip, plainText: false)
    }

    func confirmClearUnpinned() {
        isConfirmingClear = false
        guard let store else { return }
        do {
            try store.clearUnpinned()
        } catch {
            report("Couldn't clear the history.", error)
        }
        refresh(selecting: .first)
    }

    func cancelClearUnpinned() {
        isConfirmingClear = false
    }

    /// Recomputes the results from the store, query and filter.
    func refresh(selecting policy: SelectionPolicy = .keep) {
        let previousIndex = selectedIndex
        if let store {
            results = ClipSearch.results(for: query, filter: filter, pinned: store.pinned, recent: store.recent)
        } else {
            results = []
        }

        switch policy {
        case .first:
            selectedID = results.first?.id
        case .keep:
            if let selectedID, results.contains(where: { $0.id == selectedID }) { return }
            // The selected clip is gone (deleted or filtered out): select the
            // one that took its place, or the new last row.
            selectedID = results.isEmpty ? nil : results[min(previousIndex ?? 0, results.count - 1)].id
        }
    }

    // MARK: Actions

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let current = selectedIndex ?? (offset > 0 ? -1 : results.count)
        select(index: current + offset)
    }

    private func copy(_ clip: Clip?, plainText: Bool) {
        guard let clip else { return }
        guard let copier else {
            notice = "Kept can't copy while its history is unavailable."
            return
        }
        do {
            try copier.copy(clip, asPlainText: plainText)
            onDismiss()
        } catch {
            report("Couldn't copy that clip.", error)
        }
    }

    private func togglePin() {
        guard let store, let clip = selectedClip else { return }
        do {
            if clip.isPinned {
                try store.unpin(clip.id)
            } else {
                try store.pin(clip.id)
            }
        } catch {
            report(clip.isPinned ? "Couldn't unpin that clip." : "Couldn't pin that clip.", error)
        }
        refresh(selecting: .keep)
    }

    private func deleteSelection() {
        guard let store, let clip = selectedClip else { return }
        do {
            try store.delete(clip.id)
        } catch {
            report("Couldn't delete that clip.", error)
        }
        refresh(selecting: .keep)
    }

    private func requestClearUnpinned() {
        guard store != nil else { return }
        guard unpinnedCount > 0 else {
            notice = "There are no unpinned clips to clear."
            return
        }
        isConfirmingClear = true
    }

    private func cycleFilter(by offset: Int) {
        let filters = ClipFilter.allCases
        let index = filters.firstIndex(of: filter) ?? 0
        filter = filters[(index + offset % filters.count + filters.count) % filters.count]
    }

    private func report(_ message: String, _ error: any Error) {
        notice = message
        Log.panel.error("\(message, privacy: .public) \(String(describing: error), privacy: .public)")
    }

    // MARK: Observing the history

    /// Refreshes when the store changes (a new copy while the panel is open).
    private func observeHistory() {
        guard let store else { return }
        withObservationTracking {
            _ = store.pinned
            _ = store.recent
        } onChange: { [weak self] in
            let model = self
            Task { @MainActor in
                model?.historyDidChange()
            }
        }
    }

    private func historyDidChange() {
        refresh(selecting: .keep)
        observeHistory()
    }

    private static func shortened(_ text: String, limit: Int = 40) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }
}
