import Foundation
import KeptCore

/// What VoiceOver says for a clip: its kind, its text, when it was copied,
/// where from, and whether it's pinned. The list shows kinds by drawing
/// them (a swatch, a thumbnail, monospace); VoiceOver says them in words.
enum ClipAccessibility {
    /// Titles longer than this are cut, so a row reads in one breath.
    static let maxSpokenTitleCharacters = 120

    /// "Text", "Code", "Link", "Image", "3 files"…
    static func kind(of clip: Clip) -> String {
        switch clip.kind {
        case .text:
            clip.metadata.looksLikeCode ? "Code" : "Text"
        case .richText:
            clip.metadata.looksLikeCode ? "Code" : "Formatted text"
        case .link:
            "Link"
        case .image:
            "Image"
        case .file:
            (clip.metadata.fileCount ?? 1) > 1 ? "\((clip.metadata.fileCount ?? 1).formatted()) files" : "File"
        case .color:
            "Color"
        }
    }

    /// The row's label: "Link, github.com/kept, 9 minutes ago, from Safari,
    /// pinned".
    static func label(for clip: Clip, appName: String?, now: Date, calendar: Calendar = .current) -> String {
        var parts = [kind(of: clip)]
        let title = spokenTitle(of: clip)
        if !title.isEmpty { parts.append(title) }
        parts.append(AgeFormatter.copiedDescription(of: clip.lastCopiedAt, now: now, calendar: calendar))
        if let appName, !appName.isEmpty { parts.append("from \(appName)") }
        if clip.isPinned { parts.append("pinned") }
        return parts.joined(separator: ", ")
    }

    /// What VoiceOver hears when the selection moves: the label and the
    /// clip's place in the list, "… 4 of 15."
    static func announcement(
        for clip: Clip,
        position: Int,
        of count: Int,
        appName: String?,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        "\(label(for: clip, appName: appName, now: now, calendar: calendar)). \(position.formatted()) of \(count.formatted())."
    }

    /// The name the list shows (a custom title, or the generated one)
    /// without the kind said twice ("Image 1440 × 900" reads "1440 × 900"
    /// after "Image"), cut to a sentence's length.
    static func spokenTitle(of clip: Clip) -> String {
        var title = clip.displayTitle
        if clip.customTitle == nil, clip.kind == .image, title.hasPrefix("Image") {
            title = String(title.dropFirst("Image".count)).trimmingCharacters(in: .whitespaces)
        }
        guard title.count > maxSpokenTitleCharacters else { return title }
        return String(title.prefix(maxSpokenTitleCharacters)) + "…"
    }
}
