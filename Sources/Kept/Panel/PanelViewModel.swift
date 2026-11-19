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
    /// The selected clip's row in `results`.
    private(set) var selectedIndex: Int?
    /// Goes up whenever the selected row moves: another clip is selected, or
    /// the selected clip changes rows (pinned, unpinned, a pin moved, a new
    /// copy above it). The list scrolls the selection into view on each one.
    private(set) var scrollToken = 0
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
    /// The panel's frame on screen, so a copy-only hint can appear where
    /// the panel was.
    @ObservationIgnored var hintAnchor: @MainActor () -> CGRect? = { nil }
    /// Rows a PgUp / PgDn moves.
    @ObservationIgnored var pageSize = 10
    /// Opens Settings (⌘,).
    @ObservationIgnored var onOpenSettings: @MainActor () -> Void = {}
    /// Speaks a sentence to VoiceOver. The search field keeps the keyboard,
    /// so moving through the list is announced rather than focused.
    @ObservationIgnored var announce: @MainActor (String) -> Void = { _ in }

    /// The panel is off screen: history changes wait until it opens again,
    /// so a new copy never runs a search nobody sees.
    @ObservationIgnored private var isHidden = false
    /// A paste waiting for a big clip to be read off the main actor
    /// (`ClipPasting.startLoading(_:for:)`).
    @ObservationIgnored private var pendingPaste: Task<Void, Never>?

    private let paster: (any ClipPasting)?
    private let pasteOptions: @MainActor () -> PasteOptions
    private let appName: @MainActor (String) -> String?
    private let capturePaused: @MainActor () -> Bool
    /// Makes previews (big clips off the main actor) and keeps recent ones.
    private let previews: PreviewLoader

    init(
        store: HistoryStore?,
        unavailableReason: String? = nil,
        paster: (any ClipPasting)? = nil,
        pasteOptions: @escaping @MainActor () -> PasteOptions = { PasteOptions() },
        appName: @escaping @MainActor (String) -> String? = { _ in nil },
        capturePaused: @escaping @MainActor () -> Bool = { false }
    ) {
        self.store = store
        self.unavailableReason = unavailableReason
        self.paster = paster
        self.pasteOptions = pasteOptions
        self.appName = appName
        self.capturePaused = capturePaused
        previews = PreviewLoader(store: store)
        refresh(selecting: .first)
        observeHistory()
    }

    // MARK: Derived state

    var selectedClip: Clip? {
        selectedIndex.map { results[$0] }
    }

    var isCapturePaused: Bool { capturePaused() }

    var isSearching: Bool { !query.allSatisfy(\.isWhitespace) }

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
    var pinActionTitle: String { selectedClip?.isPinned == true ? "Unpin" : "Pin" }

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
        var name: String?
        if let bundleID = clip.sourceBundleID { name = appName(bundleID) }
        return ClipFacts.facts(for: clip, preview: preview, appName: name, now: now)
    }

    /// The row's accessibility label (see `ClipAccessibility`).
    func accessibilityLabel(for clip: Clip) -> String {
        var name: String?
        if let bundleID = clip.sourceBundleID { name = appName(bundleID) }
        return ClipAccessibility.label(for: clip, appName: name, now: now)
    }

    // MARK: Intents

    /// Resets the panel for a fresh look: empty query, all clips, first row.
    func prepareForShow() {
        isHidden = false
        isConfirmingClear = false
        notice = nil
        now = Date()
        query = ""
        filter = .all
        refresh(selecting: .first)
        presentationCount += 1
    }

    /// Carries out the command for a key press. Returns `false` for keys the
    /// panel leaves to the search field (text editing, and ⌘⌫ while there's
    /// a query).
    @discardableResult
    func perform(_ command: PanelCommand) -> Bool {
        switch command {
        case .edit:
            return false
        case .delete where !query.isEmpty:
            // ⌘⌫ in a text field deletes to the start of the line; only an
            // empty search makes it mean "delete this clip".
            return false
        default:
            break
        }
        if isConfirmingClear {
            confirmationKey(command)
            return true
        }
        run(command)
        return true
    }

    /// Carries out `command` on `clip`, selecting it first: the row's
    /// context menu. Its Delete works with or without a query.
    func perform(_ command: PanelCommand, on clip: Clip) {
        select(clip)
        run(command)
    }

    /// While "Clear unpinned clips?" shows, only ⌥⌘⌫ again (or the bar's
    /// button) clears. ⏎ is the paste key and gets pressed by habit, so the
    /// paste keys do nothing here; Esc and every other key back out.
    private func confirmationKey(_ command: PanelCommand) {
        switch command {
        case .requestClearUnpinned:
            confirmClearUnpinned()
        case .activate, .activateRow, .copyOnly:
            break
        default:
            isConfirmingClear = false
        }
    }

    private func run(_ command: PanelCommand) {
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
        case .activate, .copyOnly:
            if let request = command.pasteRequest { paste(selectedClip, request) }
        case .activateRow(let row, let alternate):
            if results.indices.contains(row) { paste(results[row], .paste(alternate: alternate)) }
        case .togglePin:
            togglePin()
        case .movePin(let offset):
            moveSelectedPin(by: offset)
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
        case .openSettings:
            onOpenSettings()
        case .edit:
            break
        }
        if command.movesThroughList { announceSelection() }
    }

    /// Moves the pinned `clip` being dragged to the pinned row under the
    /// pointer and selects it. Rows below the pinned section count as its
    /// last place.
    func dragPin(_ clip: Clip, toRow row: Int) {
        guard canReorderPins, clip.isPinned else { return }
        if selectedID != clip.id { select(clip) }
        movePin(clip.id, toIndex: row)
    }

    /// Selects the row at `index`, clamped to the list.
    func select(index: Int) {
        setSelection(index: results.isEmpty ? nil : min(max(index, 0), results.count - 1))
    }

    /// Selects `clip` (a click).
    func select(_ clip: Clip) {
        notice = nil
        isConfirmingClear = false
        if selectedID == clip.id { return }
        if let index = results.firstIndex(where: { $0.id == clip.id }) {
            setSelection(index: index)
        }
    }

    /// The panel went away. The query isn't kept while it's hidden, and the
    /// history isn't searched again until it opens.
    func panelDidHide() {
        isHidden = true
        pendingPaste?.cancel()
        pendingPaste = nil
        isConfirmingClear = false
        notice = nil
        query = ""
        filter = .all
    }

    /// Selects `clip` and pastes it, like ⏎ (a double-click).
    func activate(_ clip: Clip) {
        select(clip)
        paste(clip, .paste(alternate: false))
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

    /// Recomputes the results from the store, query and filter. Skipped
    /// while the panel is hidden; opening it refreshes.
    func refresh(selecting policy: SelectionPolicy = .keep) {
        guard !isHidden else { return }
        let previousID = selectedID
        let previousIndex = selectedIndex
        if let store {
            results = ClipSearch.results(for: query, filter: filter, pinned: store.pinned, recent: store.recent)
        } else {
            results = []
        }

        guard !results.isEmpty else {
            setSelection(index: nil)
            return
        }
        switch policy {
        case .first:
            setSelection(index: 0)
        case .keep:
            if let previousID, let index = results.firstIndex(where: { $0.id == previousID }) {
                setSelection(index: index)
            } else {
                // The selected clip is gone (deleted or filtered out): select
                // the one that took its place, or the new last row.
                setSelection(index: min(previousIndex ?? 0, results.count - 1))
            }
        }
    }

    /// Selects row `index` (`nil` for nothing) and bumps `scrollToken` when
    /// the selected row moved. Unchanged values aren't written, so views
    /// that read them don't update for nothing.
    private func setSelection(index: Int?) {
        let id = index.map { results[$0].id }
        guard id != selectedID || index != selectedIndex else { return }
        scrollToken &+= 1
        if id != selectedID { selectedID = id }
        if index != selectedIndex { selectedIndex = index }
    }

    // MARK: Actions

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let current = selectedIndex ?? (offset > 0 ? -1 : results.count)
        select(index: current + offset)
    }

    /// Writes `clip`, closes the panel, then pastes (or shows a hint where
    /// the panel was). If the clip can't be written the panel stays open and
    /// says so. A big clip is read off the main actor first; meanwhile
    /// another paste does nothing, and hiding the panel drops this one.
    private func paste(_ clip: Clip?, _ request: PasteRequest) {
        guard let clip else { return }
        guard let paster else {
            notice = "Kept can't paste while its history is unavailable."
            return
        }
        guard pendingPaste == nil else { return }
        guard let loading = paster.startLoading(clip, for: request) else {
            write(clip, request)
            return
        }
        pendingPaste = Task { [weak self] in
            await withTaskCancellationHandler {
                await loading.value
            } onCancel: {
                loading.cancel()
            }
            guard let self, !Task.isCancelled else { return }
            self.pendingPaste = nil
            self.write(clip, request)
        }
    }

    /// The second half of `paste(_:_:)`, once anything slow has been read.
    private func write(_ clip: Clip, _ request: PasteRequest) {
        guard let paster else { return }
        let plan: PastePlan
        do {
            plan = try paster.prepare(clip, for: request)
        } catch {
            report("Couldn't copy that clip.", error)
            return
        }
        let anchor = hintAnchor()
        onDismiss()
        paster.complete(plan, anchor: anchor)
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

    /// ⌥⌘↑ / ⌥⌘↓: the selected pin swaps places with its neighbor.
    private func moveSelectedPin(by offset: Int) {
        guard canReorderPins, let store, let clip = selectedClip, clip.isPinned,
              let index = store.pinned.firstIndex(where: { $0.id == clip.id })
        else { return }
        movePin(clip.id, toIndex: index + offset)
    }

    /// Moves a pin to `index` in the pinned section (clamped); it stays
    /// selected if it was.
    private func movePin(_ id: UUID, toIndex index: Int) {
        guard let store, let from = store.pinned.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(index, 0), store.pinned.count - 1)
        guard target != from else { return }
        do {
            try store.movePin(id, toIndex: target)
        } catch {
            report("Couldn't move that pin.", error)
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
            let message = "There are no unpinned clips to clear."
            notice = message
            announce(message)
            return
        }
        isConfirmingClear = true
        announce("\(clearConfirmationMessage) Press Option-Command-Delete again to clear them, or Escape to cancel.")
    }

    private func cycleFilter(by offset: Int) {
        let filters = ClipFilter.allCases
        let index = filters.firstIndex(of: filter) ?? 0
        filter = filters[(index + offset % filters.count + filters.count) % filters.count]
    }

    /// Tells VoiceOver which clip is selected now, since the search field
    /// keeps the keyboard focus: "Link, github.com/…, 9 minutes ago, from
    /// Safari. 4 of 15."
    private func announceSelection() {
        guard let clip = selectedClip, let index = selectedIndex else {
            if let emptyState { announce(emptyState.title) }
            return
        }
        var name: String?
        if let bundleID = clip.sourceBundleID { name = appName(bundleID) }
        announce(ClipAccessibility.announcement(
            for: clip,
            position: index + 1,
            of: results.count,
            appName: name,
            now: Date()
        ))
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

    /// A new copy (or any other change) while the panel is open keeps the
    /// selected clip selected. While it's hidden nothing is searched; opening
    /// the panel refreshes.
    private func historyDidChange() {
        refresh(selecting: .keep)
        observeHistory()
    }

    private static func shortened(_ text: String, limit: Int = 40) -> String {
        text.count > limit ? String(text.prefix(limit)) + "…" : text
    }
}
