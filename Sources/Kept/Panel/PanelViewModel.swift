import Foundation
import KeptCore
import Observation

/// The panel's state and behavior: the query and type filter, the visible
/// clips (from `ClipSearch`), the selection, and every action the keyboard
/// or mouse can take. Views render it; `PanelKeyRouter` feeds it commands.
///
/// Every stored property lives here, so observation tracks all of it; the
/// behavior is split by concern, and only the model and its extensions
/// write its state:
///
/// - `PanelViewModel+Display.swift`: what views read (titles, the empty
///   state, previews, facts, accessibility)
/// - `PanelViewModel+Actions.swift`: pasting, pins, deleting, clearing,
///   filters
/// - `PanelViewModel+Editing.swift`: renaming (⌘R) and editing text (⌘E)
@MainActor
@Observable
final class PanelViewModel {
    enum SelectionPolicy {
        /// Select the first result (after the query or filter changed).
        case first
        /// Keep the selected clip; if it's gone, select whatever took its place.
        case keep
    }

    /// The search text. Changing it selects the best match (and saves a
    /// name or text being edited).
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            isConfirmingClear = false
            finishEditing()
            refresh(selecting: .first)
        }
    }

    /// The type filter. Changing it selects the first result (and saves a
    /// name or text being edited).
    var filter: ClipFilter = .all {
        didSet {
            guard filter != oldValue else { return }
            finishEditing()
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
    var isConfirmingClear = false
    /// A short message about something that went wrong, shown in the footer.
    var notice: String?
    /// Goes up each time the panel opens, so views can refocus and scroll.
    private(set) var presentationCount = 0
    /// The time ages are measured from; updated when the panel opens.
    private(set) var now = Date()
    /// A clip's name or text being edited, or `nil`.
    var editing: PanelEditing?
    /// The name being typed into the row (⌘R).
    var nameDraft = ""
    /// The text being typed into the preview (⌘E).
    var textDraft = ""
    /// Goes up when a name or text stops being edited, so the search
    /// field takes the keyboard back.
    var searchFocusToken = 0

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
    @ObservationIgnored var pendingPaste: Task<Void, Never>?
    /// A big clip's text being read off the main actor before ⌘E edits it.
    @ObservationIgnored var pendingTextEdit: Task<Void, Never>?

    let paster: (any ClipPasting)?
    let pasteOptions: @MainActor () -> PasteOptions
    let appName: @MainActor (String) -> String?
    let capturePaused: @MainActor () -> Bool
    /// Makes previews (big clips off the main actor) and keeps recent ones.
    let previews: PreviewLoader

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

    var selectedClip: Clip? {
        selectedIndex.map { results[$0] }
    }

    var isSearching: Bool { !query.allSatisfy(\.isWhitespace) }

    /// How `PanelKeyRouter` reads keys: in the search field, or in the name
    /// or text being edited.
    var keyMode: PanelKeyMode { editing?.keyMode ?? .browsing }

    /// The clip whose name is being edited in its row.
    var renamingID: UUID? {
        if case .name(let id) = editing { id } else { nil }
    }

    /// The text being edited in the preview, if any.
    var textEdit: PanelEditing.TextEdit? {
        if case .text(let edit) = editing { edit } else { nil }
    }

    // MARK: Showing and hiding

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

    /// The panel went away. The query isn't kept while it's hidden, and the
    /// history isn't searched again until it opens.
    func panelDidHide() {
        // Moving away saves, as clicking elsewhere does.
        finishEditing()
        isHidden = true
        pendingPaste?.cancel()
        pendingPaste = nil
        isConfirmingClear = false
        notice = nil
        query = ""
        filter = .all
    }

    // MARK: Commands

    /// Carries out the command for a key press. Returns `false` for keys the
    /// panel leaves to the search field (text editing, and ⌘⌫ while there's
    /// a query). While a name or text is being edited, only saving and
    /// cancelling do anything.
    @discardableResult
    func perform(_ command: PanelCommand) -> Bool {
        switch command {
        case .edit:
            return false
        case .ignore:
            return true
        case .delete where !query.isEmpty && editing == nil:
            // ⌘⌫ in a text field deletes to the start of the line; only an
            // empty search makes it mean "delete this clip".
            return false
        default:
            break
        }
        if editing != nil {
            switch command {
            case .commitEditing: commitEditing()
            case .cancelEditing: cancelEditing()
            default: break
            }
            return true
        }
        if isConfirmingClear {
            confirmationKey(command)
            return true
        }
        run(command)
        return true
    }

    /// Carries out `command` on `clip`, selecting it first: the row's
    /// context menu. Its Delete works with or without a query. A name or
    /// text being edited is saved first.
    func perform(_ command: PanelCommand, on clip: Clip) {
        finishEditing()
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
        case .beginRename:
            beginRename()
        case .beginTextEdit:
            beginTextEdit()
        case .commitEditing, .cancelEditing, .ignore, .edit:
            break
        }
        if command.movesThroughList { announceSelection() }
    }

    /// Shows `message` in the footer and logs it with `error`.
    func report(_ message: String, _ error: any Error) {
        notice = message
        Log.panel.error("\(message, privacy: .public) \(String(describing: error), privacy: .public)")
    }

    // MARK: Selection

    /// Selects the row at `index`, clamped to the list.
    func select(index: Int) {
        setSelection(index: results.isEmpty ? nil : min(max(index, 0), results.count - 1))
    }

    /// Selects `clip` (a click). Clicking away from a name or text being
    /// edited saves it.
    func select(_ clip: Clip) {
        notice = nil
        isConfirmingClear = false
        // After clearing the notice, so one about the save stays.
        if let editing, editing.clipID != clip.id { finishEditing() }
        if selectedID == clip.id { return }
        if let index = results.firstIndex(where: { $0.id == clip.id }) {
            setSelection(index: index)
        }
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

        // The clip being edited went away (deleted or cleared elsewhere):
        // there's nothing to save it to.
        if let editing, !results.contains(where: { $0.id == editing.clipID }) {
            endEditing()
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

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let current = selectedIndex ?? (offset > 0 ? -1 : results.count)
        select(index: current + offset)
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
}
