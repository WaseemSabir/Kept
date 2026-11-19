import KeptCore
import SwiftUI

/// A clip drawn in one line, by kind: prose in SF Pro, code in SF Mono, a
/// link as its host and muted path, a color as its swatch, an image as its
/// thumbnail, files as their icon and name. No kind labels. When selected,
/// the highlighter goes behind the text only, never over a glyph, and the
/// text takes the marked ink (dark on yellow in dark mode). While
/// searching, the words that match are set a weight heavier, in the same ink,
/// and a text row whose first match would be truncated starts just before it.
/// A clip the user named shows its name, then its content muted, after
/// its glyph.
struct ClipSummary: View {
    let clip: Clip
    let isMarked: Bool
    /// The query's words; where they match, the text is semibold.
    var matchTokens: [String] = []
    let resources: PanelResources
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let name = clip.customTitle {
            HStack(spacing: Theme.Spacing.glyphGap) {
                if ClipGlyph.shows(clip) {
                    ClipGlyph(clip: clip, resources: resources)
                }
                line(twoTone(name, "  " + clip.title, isCode: false), isCode: false)
            }
        } else {
            summary
        }
    }

    @ViewBuilder
    private var summary: some View {
        switch clip.kind {
        case .text, .richText:
            // A match deep in the text would be truncated away; start the
            // line just before it instead.
            let isCode = clip.metadata.looksLikeCode
            let text = MatchHighlighter.excerpt(of: clip.title, tokens: matchTokens)
            line(emphasized(text, isCode: isCode), isCode: isCode)
        case .link:
            let parts = ClipDisplay.linkParts(of: clip.title)
            line(twoTone(parts.host, parts.rest, isCode: false), isCode: false)
        case .color:
            HStack(spacing: Theme.Spacing.glyphGap) {
                ClipGlyph(clip: clip, resources: resources)
                line(emphasized(clip.title, isCode: true), isCode: true)
            }
        case .image:
            HStack(spacing: Theme.Spacing.glyphGap) {
                ClipGlyph(clip: clip, resources: resources)
                line(emphasized(clip.title, isCode: false), isCode: false)
            }
        case .file:
            HStack(spacing: Theme.Spacing.glyphGap) {
                ClipGlyph(clip: clip, resources: resources)
                line(fileText, isCode: false)
            }
        }
    }

    private func line(_ text: AttributedString, isCode: Bool) -> some View {
        Text(text)
            .font(isCode ? Theme.Typography.rowCode : Theme.Typography.rowTitle)
            .foregroundStyle(isMarked ? Theme.Colors.markedInk(colorScheme) : Theme.Colors.ink)
            .lineLimit(1)
            .truncationMode(.tail)
            .marked(isMarked)
    }

    /// "3 files" followed by their names, muted; one file's name alone.
    private var fileText: AttributedString {
        let names = (clip.metadata.fileCount ?? 1) > 1 ? "  " + clip.title : ""
        return twoTone(ClipDisplay.fileSummary(of: clip), names, isCode: false)
    }

    /// `primary` in ink, then `secondary` muted (both in the marked inks
    /// when selected), matches emphasized in both.
    private func twoTone(_ primary: String, _ secondary: String, isCode: Bool) -> AttributedString {
        typealias Foreground = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
        var first = emphasized(primary, isCode: isCode)
        first[Foreground.self] = isMarked ? Theme.Colors.markedInk(colorScheme) : Theme.Colors.ink
        var second = emphasized(secondary, isCode: isCode)
        second[Foreground.self] = isMarked ? Theme.Colors.markedInkMuted(colorScheme) : Theme.Colors.inkMuted
        return first + second
    }

    /// `text` with the runs that match the query in the row's font, a
    /// weight heavier.
    private func emphasized(_ text: String, isCode: Bool) -> AttributedString {
        typealias FontAttribute = AttributeScopes.SwiftUIAttributes.FontAttribute
        guard !matchTokens.isEmpty else { return AttributedString(text) }
        let matchFont = isCode ? Theme.Typography.rowCodeMatch : Theme.Typography.rowTitleMatch
        var result = AttributedString()
        for run in MatchHighlighter.runs(of: text, tokens: matchTokens) {
            var piece = AttributedString(String(run.text))
            if run.isMatch { piece[FontAttribute.self] = matchFont }
            result += piece
        }
        return result
    }
}
