/// The type filter in the panel (Tab / ⇧Tab cycles through it).
public enum ClipFilter: String, Sendable, Hashable, CaseIterable {
    case all
    case pinned
    /// Plain and rich text, colors and code.
    case text
    case links
    case images
    case files

    public func includes(_ clip: Clip) -> Bool {
        switch self {
        case .all: true
        case .pinned: clip.isPinned
        case .text: clip.kind == .text || clip.kind == .richText || clip.kind == .color
        case .links: clip.kind == .link
        case .images: clip.kind == .image
        case .files: clip.kind == .file
        }
    }
}
