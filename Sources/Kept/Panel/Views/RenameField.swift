import KeptCore
import SwiftUI

/// The selected row's name field while renaming (⌘R): a native rounded
/// field after the clip's glyph, holding its name or title, all of it
/// selected so typing replaces it. Empty, it shows the clip's own title as
/// the placeholder, which is what an empty name brings back.
///
/// ⏎ and Esc reach the model through the panel's key router; clicking
/// elsewhere (the field losing the keyboard) saves, like Finder.
struct RenameField: View {
    @Bindable var model: PanelViewModel
    let clip: Clip
    let resources: PanelResources
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.glyphGap) {
            if ClipGlyph.shows(clip) {
                ClipGlyph(clip: clip, resources: resources)
            }
            TextField("Name", text: $model.nameDraft, prompt: Text(clip.title))
                .textFieldStyle(.roundedBorder)
                .font(Theme.Typography.rowTitle)
                .focused($isFocused)
                // Its text lines up with the other rows'; after a glyph,
                // the bezel keeps its distance instead.
                .padding(.leading, ClipGlyph.shows(clip) ? 0 : -Theme.Layout.renameFieldInset)
                .onSubmit { model.commitEditing() }
                .accessibilityLabel("Name")
                .accessibilityHint("Press Return to save, or Escape to cancel. Leave it empty to show the clip's text.")
        }
        .onAppear {
            // After the row is on screen, or focus doesn't move.
            Task { @MainActor in isFocused = true }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { model.renameFieldDidResign(for: clip.id) }
        }
    }
}
