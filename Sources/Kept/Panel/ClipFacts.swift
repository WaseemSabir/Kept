import Foundation
import KeptCore

/// One line of the preview's fact list: a label and its value.
struct ClipFact: Identifiable, Equatable, Sendable {
    let label: String
    let value: String
    /// Draws this app's icon before the value (for "From").
    var appBundleID: String?
    /// Cuts a long value at its end ("Content") rather than its middle.
    var truncatesTail = false

    var id: String { label }
}

/// The facts the preview lists under a clip: where it came from, when, how
/// often, and how big; for a clip the user named, last, the start of what it
/// holds. Values are words and numbers, never dot-joined strings.
enum ClipFacts {
    /// The longest "Content" value, in characters.
    static let maxContentCharacters = 200

    static func facts(
        for clip: Clip,
        preview: ClipPreview,
        appName: String?,
        now: Date,
        calendar: Calendar = .current
    ) -> [ClipFact] {
        var facts: [ClipFact] = []
        if let bundleID = clip.sourceBundleID {
            facts.append(ClipFact(label: "From", value: appName ?? bundleID, appBundleID: bundleID))
        }
        facts.append(ClipFact(
            label: "Copied",
            value: AgeFormatter.copiedDescription(of: clip.lastCopiedAt, now: now, calendar: calendar)
        ))
        if clip.copyCount > 1 {
            facts.append(ClipFact(label: "Times copied", value: clip.copyCount.formatted()))
        }
        facts += kindFacts(for: clip, preview: preview)
        if let name = clip.customTitle {
            let content = contentLine(of: clip, preview: preview)
            if !content.isEmpty, content != name {
                facts.append(ClipFact(label: "Content", value: content, truncatesTail: true))
            }
        }
        return facts
    }

    /// What a named clip holds, in one line: its text's first line with
    /// something in it, or the generated title (a link, a color, an
    /// image's size, file names).
    static func contentLine(of clip: Clip, preview: ClipPreview) -> String {
        var line = clip.title
        if case .text(let text, _) = preview.content,
           let first = text.split(separator: "\n", omittingEmptySubsequences: true)
               .lazy.map({ $0.trimmingCharacters(in: .whitespaces) })
               .first(where: { !$0.isEmpty }) {
            line = first
        }
        guard line.count > maxContentCharacters else { return line }
        return String(line.prefix(maxContentCharacters)) + "…"
    }

    private static func kindFacts(for clip: Clip, preview: ClipPreview) -> [ClipFact] {
        let metadata = clip.metadata
        switch clip.kind {
        case .text, .richText:
            var facts: [ClipFact] = []
            if let characters = metadata.characterCount {
                facts.append(ClipFact(label: "Size", value: ClipDisplay.count(characters, "character", "characters")))
            }
            if let lines = preview.lineCount, lines > 1 {
                facts.append(ClipFact(label: "Lines", value: lines.formatted()))
            }
            if clip.kind == .richText {
                facts.append(ClipFact(label: "Format", value: "Rich text"))
            }
            return facts

        case .link:
            guard let characters = metadata.characterCount else { return [] }
            return [ClipFact(label: "Size", value: ClipDisplay.count(characters, "character", "characters"))]

        case .color:
            guard let hex = metadata.colorHex, let rgba = ClipDisplay.rgba(fromHex: hex) else { return [] }
            var facts = [ClipFact(label: "RGB", value: "\(rgba.red), \(rgba.green), \(rgba.blue)")]
            if rgba.alpha < 255 {
                let percent = Int((Double(rgba.alpha) / 255 * 100).rounded())
                facts.append(ClipFact(label: "Opacity", value: "\(percent)%"))
            }
            return facts

        case .image:
            var facts: [ClipFact] = []
            if let size = metadata.imagePixelSize {
                facts.append(ClipFact(label: "Dimensions", value: "\(size.width) × \(size.height)"))
            }
            facts.append(ClipFact(label: "Size", value: Int64(clip.byteSize).formatted(.byteCount(style: .file))))
            if let format = ClipDisplay.imageFormatName(metadata.imageType) {
                facts.append(ClipFact(label: "Format", value: format))
            }
            return facts

        case .file:
            let count = metadata.fileCount ?? 1
            return count > 1 ? [ClipFact(label: "Files", value: count.formatted())] : []
        }
    }
}
