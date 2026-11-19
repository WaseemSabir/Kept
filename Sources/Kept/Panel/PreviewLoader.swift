import Foundation
import KeptCore

/// Makes clips' previews from the store and keeps the most recent ones.
///
/// Only the representations a preview shows are read (a text clip's text
/// types, a file clip's URLs), never the picture an app put next to its
/// text. Small clips are previewed at once, on the main actor; bigger ones
/// are read and prepared off it (`load(_:)`), and a load the panel no
/// longer wants is cancelled. Every string it returns, file paths
/// included, has been through `TextSanitizer.multiline(_:maxUTF16Count:)`,
/// so a hostile clip can't stall text layout, and lines are counted on
/// bytes.
@MainActor
final class PreviewLoader {
    /// The most text the preview lays out, in UTF-16 code units (one per
    /// character for most text); the pane says when there's more.
    nonisolated static let maxCharacters = 20_000
    /// The longest file path shown, in UTF-16 code units.
    nonisolated static let maxPathLength = 4_096
    /// Clips whose shown representations are all in the database and add
    /// up to at most this many bytes are previewed at once.
    static let immediateByteLimit = 64 * 1024
    /// How many previews are kept.
    nonisolated static let cacheCount = 16

    /// A clip as previewed: an edit changes its content (and hash) but
    /// not its ID or dates.
    private struct Key: Hashable, Sendable {
        let id: UUID
        let contentHash: String
        let lastCopiedAt: Date
        let copyCount: Int

        init(_ clip: Clip) {
            id = clip.id
            contentHash = clip.contentHash
            lastCopiedAt = clip.lastCopiedAt
            copyCount = clip.copyCount
        }
    }

    /// How to make a text or file preview from a clip's items: what it needs
    /// of the clip, as a value that can go to the load.
    private struct Recipe: Sendable {
        let showsFiles: Bool
        let isCode: Bool
        let characterCount: Int?
        /// Shown when the items have no text.
        let fallbackText: String

        init(_ clip: Clip) {
            showsFiles = clip.kind == .file
            isCode = clip.metadata.looksLikeCode
            characterCount = clip.metadata.characterCount
            fallbackText = clip.searchText
        }

        var types: Set<PasteboardType> {
            showsFiles ? [.fileURL] : Set(PasteboardItem.textTypes)
        }
    }

    private enum Plan {
        case ready(ClipPreview)
        case read(StoredRepresentations, Recipe)
    }

    private let store: HistoryStore?
    private var cache = LRUCache<Key, ClipPreview>(countLimit: PreviewLoader.cacheCount)
    private let loads = SharedLoads<Key, ClipPreview>()

    init(store: HistoryStore?) {
        self.store = store
    }

    /// The clip's preview when it's kept from before or quick to make now;
    /// `.loading` while a big clip still has to be read (`load(_:)`).
    func preview(for clip: Clip) -> ClipPreview {
        let key = Key(clip)
        if let cached = cache.value(for: key) { return cached }
        if loads.isLoading(key) { return ClipPreview(.loading) }

        let preview: ClipPreview
        switch plan(for: clip) {
        case .ready(let ready):
            preview = ready
        case .read(let stored, let recipe):
            guard stored.isInMemory, stored.byteSize <= Self.immediateByteLimit,
                  let made = Self.make(from: stored, recipe)
            else { return ClipPreview(.loading) }
            preview = made
        }
        cache.insert(preview, for: key)
        return preview
    }

    /// The clip's preview, reading and preparing it off the main actor
    /// unless it's kept from before; kept for next time. `nil` when the
    /// caller was cancelled (another clip was selected).
    func load(_ clip: Clip) async -> ClipPreview? {
        let key = Key(clip)
        if let cached = cache.value(for: key) { return cached }

        let preview: ClipPreview?
        switch plan(for: clip) {
        case .ready(let ready):
            preview = ready
        case .read(let stored, let recipe):
            preview = await loads.value(for: key) { PreviewLoader.make(from: stored, recipe) }
        }
        guard let preview, !Task.isCancelled else { return nil }
        cache.insert(preview, for: key)
        return preview
    }

    /// The preview for kinds that need no stored data, or where to find the
    /// data for the others (a quick database query; blob files aren't read).
    private func plan(for clip: Clip) -> Plan {
        switch clip.kind {
        case .image:
            return .ready(ClipPreview(.image))
        case .color:
            return .ready(ClipPreview(.color(hex: clip.metadata.colorHex ?? clip.title, text: clip.title)))
        case .link:
            // A link has no whitespace, so its sanitized title is the whole URL.
            return .ready(ClipPreview(.link(clip.title)))
        case .file, .text, .richText:
            guard let store else { return .ready(ClipPreview(.unavailable("History isn't available."))) }
            let recipe = Recipe(clip)
            do {
                return .read(try store.storedRepresentations(for: clip.id, types: recipe.types), recipe)
            } catch {
                Log.panel.error("Couldn't find a clip to preview: \(String(describing: error), privacy: .public)")
                return .ready(ClipPreview(.unavailable("Kept couldn't load this clip.")))
            }
        }
    }

    // MARK: Making previews (anywhere)

    /// Reads `stored` and makes the preview; `nil` if the task was cancelled.
    private nonisolated static func make(from stored: StoredRepresentations, _ recipe: Recipe) -> ClipPreview? {
        let items: [PasteboardItem]
        do {
            items = try stored.load()
        } catch {
            Log.panel.error("Couldn't load a preview: \(String(describing: error), privacy: .public)")
            return ClipPreview(.unavailable("Kept couldn't load this clip."))
        }
        guard !Task.isCancelled else { return nil }

        if recipe.showsFiles {
            let paths = items.compactMap { $0.data(for: .fileURL) }.map { displayPath(fromURLData: $0) }
            return ClipPreview(.files(paths))
        }
        let text = PasteboardItem.plainText(of: items) ?? recipe.fallbackText
        return textPreview(text, isCode: recipe.isCode, characterCount: recipe.characterCount)
    }

    /// The text shown for `text`: sanitized and cut at `maxCharacters`, with
    /// the full text's line count. `characterCount` is the full text's
    /// length when known (the clip's metadata), which saves counting it.
    nonisolated static func textPreview(_ text: String, isCode: Bool, characterCount: Int? = nil) -> ClipPreview {
        let excerpt = TextSanitizer.multiline(text, maxUTF16Count: maxCharacters)
        var preview = ClipPreview(.text(excerpt.text, isCode: isCode), lineCount: TextSanitizer.lineCount(of: text))
        if excerpt.isTruncated {
            let shown = excerpt.text.count
            preview.shownCharacterCount = shown
            preview.truncatedFrom = max(characterCount ?? text.count, shown + 1)
        }
        return preview
    }

    /// A file URL's path, sanitized for display (file names may hold any
    /// character but `/`); the text as is when it isn't a file URL.
    nonisolated static func displayPath(fromURLData data: Data) -> String {
        var text = String(decoding: data, as: UTF8.self)
        while text.hasSuffix("\u{0}") { text.removeLast() }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = URL(string: text).flatMap { $0.isFileURL ? $0.path : nil } ?? text
        return TextSanitizer.multiline(path, maxUTF16Count: maxPathLength).text
    }
}
