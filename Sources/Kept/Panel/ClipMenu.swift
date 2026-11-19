import KeptCore

/// What a row's context menu offers for a clip, section by section (the
/// view draws dividers between them): the paste actions, then pin, rename
/// and edit (text-like clips only), then delete. Named as the footer names
/// them; the view adds each command's key.
enum ClipMenu {
    struct Item: Equatable, Sendable {
        let title: String
        let command: PanelCommand
    }

    static func sections(
        for clip: Clip,
        primaryTitle: String,
        alternateTitle: String,
        copyOnlyTitle: String?
    ) -> [[Item]] {
        var paste = [
            Item(title: primaryTitle, command: .activate(alternate: false)),
            Item(title: alternateTitle, command: .activate(alternate: true)),
        ]
        if let copyOnlyTitle {
            paste.append(Item(title: copyOnlyTitle, command: .copyOnly))
        }
        var change = [
            Item(title: pinTitle(for: clip), command: .togglePin),
            Item(title: "Rename…", command: .beginRename),
        ]
        if clip.kind.isTextLike {
            change.append(Item(title: "Edit…", command: .beginTextEdit))
        }
        return [paste, change, [Item(title: "Delete", command: .delete)]]
    }

    /// What pinning does to `clip`: "Pin", or "Unpin" for a pinned clip.
    static func pinTitle(for clip: Clip) -> String {
        clip.isPinned ? "Unpin" : "Pin"
    }
}
