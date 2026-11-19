/// What the preview pane shows for one clip, loaded from its stored
/// representations when the clip is selected.
struct ClipPreview: Equatable, Sendable {
    enum Content: Equatable, Sendable {
        /// Full text with its line breaks; `isCode` sets it in SF Mono.
        case text(String, isCode: Bool)
        case link(String)
        /// `hex` is `#RRGGBB(AA)`; `text` is the value as copied.
        case color(hex: String, text: String)
        /// Drawn from the thumbnail cache.
        case image
        /// File paths.
        case files([String])
        /// Why nothing can be shown.
        case unavailable(String)
        /// A big clip is still being read, off the main actor.
        case loading
    }

    var content: Content
    /// Lines in the full text, for text clips.
    var lineCount: Int?
    /// The full text's length in characters when `content` holds only its start.
    var truncatedFrom: Int?
    /// How many characters `content` shows when it holds only the start.
    var shownCharacterCount: Int?

    init(_ content: Content, lineCount: Int? = nil, truncatedFrom: Int? = nil, shownCharacterCount: Int? = nil) {
        self.content = content
        self.lineCount = lineCount
        self.truncatedFrom = truncatedFrom
        self.shownCharacterCount = shownCharacterCount
    }
}
