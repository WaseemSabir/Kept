import Foundation
import KeptCore

/// Renaming a clip in its row (⌘R) and editing its text in the preview
/// (⌘E). Moving away saves; only Esc discards.
@MainActor
extension PanelViewModel {
    /// The most characters the preview's editor takes; longer clips can't
    /// be edited in Kept.
    static let maxEditableCharacters = 100_000

    /// ⌘R: the selected row's title becomes a field holding its name (or
    /// title), for `commitRename()`.
    func beginRename() {
        guard let clip = selectedClip else { return }
        finishEditing()
        notice = nil
        nameDraft = clip.displayTitle
        editing = .name(clipID: clip.id)
    }

    /// ⌘E: the preview becomes an editor for the selected clip's text.
    /// Images and files can't be edited (the footer says so and suggests
    /// ⌘R); a big clip is read off the main actor first.
    func beginTextEdit() {
        guard let clip = selectedClip, let store else { return }
        finishEditing()
        notice = nil
        guard clip.kind.isTextLike else {
            let message = Self.notEditableMessage(for: clip)
            notice = message
            announce(message)
            return
        }
        if let count = clip.metadata.characterCount, count > Self.maxEditableCharacters {
            refuseTooLongEdit()
            return
        }
        let stored: StoredRepresentations
        do {
            stored = try store.storedRepresentations(for: clip.id, types: Set(PasteboardItem.textTypes))
        } catch {
            report("Couldn't open that clip for editing.", error)
            return
        }
        if stored.isInMemory, stored.byteSize <= PreviewLoader.immediateByteLimit {
            startTextEdit(of: clip, text: Self.editableText(of: stored))
            return
        }
        pendingTextEdit?.cancel()
        let id = clip.id
        pendingTextEdit = Task { [weak self] in
            let text = await Task.detached(priority: .userInitiated) {
                PanelViewModel.editableText(of: stored)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.pendingTextEdit = nil
            guard let clip = self.selectedClip, clip.id == id else { return }
            self.startTextEdit(of: clip, text: text)
        }
    }

    /// Saves the name or text being edited (⏎ or ⌘S); the same as
    /// `finishEditing()` except that text that can't be saved stays in the
    /// editor with a notice.
    func commitEditing() {
        switch editing {
        case .name: commitRename()
        case .text: commitTextEdit(keepingOnFailure: true)
        case nil: break
        }
    }

    /// Esc: puts the name or text back as it was.
    func cancelEditing() {
        guard editing != nil else { return }
        notice = nil
        endEditing()
    }

    /// Saves the name or text being edited because the user moved away
    /// from it: clicked elsewhere, searched, or closed the panel.
    func finishEditing() {
        pendingTextEdit?.cancel()
        pendingTextEdit = nil
        switch editing {
        case .name: commitRename()
        case .text: commitTextEdit(keepingOnFailure: false)
        case nil: break
        }
    }

    /// The name field lost the keyboard (a click elsewhere): saves it if
    /// it's still `clipID`'s.
    func renameFieldDidResign(for clipID: UUID) {
        guard renamingID == clipID else { return }
        commitRename()
    }

    /// The text editor lost the keyboard (a click in the search field):
    /// saves it if it's still `clipID`'s.
    func textEditorDidResign(for clipID: UUID) {
        guard textEdit?.clipID == clipID else { return }
        commitTextEdit(keepingOnFailure: false)
    }

    /// Stops editing without saving, and gives the keyboard back to the
    /// search field.
    func endEditing() {
        guard editing != nil else { return }
        editing = nil
        searchFocusToken &+= 1
    }

    /// Code, links and colors are edited in SF Mono, as the preview shows them.
    static func editsAsCode(_ clip: Clip) -> Bool {
        clip.metadata.looksLikeCode || clip.kind == .link || clip.kind == .color
    }

    /// Why ⌘E does nothing for an image or files, and what to do instead;
    /// short enough for the footer beside its key hints.
    static func notEditableMessage(for clip: Clip) -> String {
        switch clip.kind {
        case .image: "Images can't be edited. ⌘R renames it."
        case .file where (clip.metadata.fileCount ?? 1) > 1: "Files can't be edited. ⌘R renames them."
        default: "Files can't be edited. ⌘R renames it."
        }
    }

    // MARK: Saving

    private func commitRename() {
        guard case .name(let id) = editing, let store else { return }
        let name = nameDraft
        endEditing()
        do {
            let renamed = try store.rename(id, to: name)
            announce(renamed.customTitle.map { "Renamed to \($0)." } ?? "Name removed.")
        } catch {
            report("Couldn't rename that clip.", error)
        }
        refresh(selecting: .keep)
    }

    private func commitTextEdit(keepingOnFailure: Bool) {
        guard let edit = textEdit, let store else { return }
        let text = textDraft
        guard text != edit.original else {
            endEditing()
            return
        }
        do throws(HistoryStoreError) {
            try store.editText(edit.clipID, to: text, at: Date())
            endEditing()
            notice = nil
            announce("Edit saved.")
        } catch .emptyText {
            if keepingOnFailure {
                notice = "Type some text to save, or press Esc to cancel."
                announce(notice ?? "")
                return
            }
            endEditing()
            notice = "An empty edit wasn't saved."
        } catch {
            report("Couldn't save your edit.", error)
            if keepingOnFailure { return }
            endEditing()
        }
        refresh(selecting: .keep)
    }

    // MARK: Starting a text edit

    private func startTextEdit(of clip: Clip, text: String?) {
        guard let text else {
            // Never edit a stand-in (the search text is cut and collapsed).
            notice = "Couldn't open that clip for editing."
            Log.panel.error("A clip to edit has no readable text")
            return
        }
        let excerpt = TextSanitizer.multiline(text, maxUTF16Count: Self.maxEditableCharacters)
        guard !excerpt.isTruncated else {
            refuseTooLongEdit()
            return
        }
        textDraft = excerpt.text
        editing = .text(PanelEditing.TextEdit(
            clipID: clip.id,
            original: excerpt.text,
            dropsFormatting: clip.kind == .richText,
            isCode: Self.editsAsCode(clip)
        ))
    }

    private func refuseTooLongEdit() {
        let message = "Kept edits up to \(Self.maxEditableCharacters.formatted()) characters."
        notice = message
        announce(message)
    }

    /// The clip's text as the editor shows it: its plain text (string,
    /// URL, RTF, then HTML), read wherever this runs; `nil` when it can't
    /// be read.
    private nonisolated static func editableText(of stored: StoredRepresentations) -> String? {
        do {
            return PasteboardItem.plainText(of: try stored.load())
        } catch {
            Log.panel.error("Couldn't read a clip to edit: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
