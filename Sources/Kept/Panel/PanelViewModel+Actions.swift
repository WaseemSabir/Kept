import Foundation
import KeptCore

/// What the panel does to clips: paste or copy them, pin and reorder them,
/// delete them, clear the history, and cycle the type filter.
@MainActor
extension PanelViewModel {
    // MARK: Pasting

    /// Selects `clip` and pastes it, like ⏎ (a double-click). A name or
    /// text being edited is saved first, so an edited clip pastes as edited.
    func activate(_ clip: Clip) {
        guard renamingID != clip.id else { return }
        finishEditing()
        select(clip)
        paste(store?.clip(withID: clip.id) ?? clip, .paste(alternate: false))
    }

    /// Writes `clip`, closes the panel, then pastes (or shows a hint where
    /// the panel was). If the clip can't be written the panel stays open and
    /// says so. A big clip is read off the main actor first; meanwhile
    /// another paste does nothing, and hiding the panel drops this one.
    func paste(_ clip: Clip?, _ request: PasteRequest) {
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

    // MARK: Pins

    func togglePin() {
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

    /// Moves the pinned `clip` being dragged to the pinned row under the
    /// pointer and selects it. Rows below the pinned section count as its
    /// last place.
    func dragPin(_ clip: Clip, toRow row: Int) {
        guard canReorderPins, clip.isPinned else { return }
        if selectedID != clip.id { select(clip) }
        movePin(clip.id, toIndex: row)
    }

    /// ⌥⌘↑ / ⌥⌘↓: the selected pin swaps places with its neighbor.
    func moveSelectedPin(by offset: Int) {
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

    // MARK: Deleting and clearing

    func deleteSelection() {
        guard let store, let clip = selectedClip else { return }
        do {
            try store.delete(clip.id)
        } catch {
            report("Couldn't delete that clip.", error)
        }
        refresh(selecting: .keep)
    }

    /// ⌥⌘⌫: shows the inline "Clear unpinned clips?" bar, or says there's
    /// nothing to clear.
    func requestClearUnpinned() {
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

    // MARK: Filters

    /// Tab / ⇧Tab: the next or previous type filter, wrapping around.
    func cycleFilter(by offset: Int) {
        let filters = ClipFilter.allCases
        let index = filters.firstIndex(of: filter) ?? 0
        filter = filters[(index + offset % filters.count + filters.count) % filters.count]
    }
}
