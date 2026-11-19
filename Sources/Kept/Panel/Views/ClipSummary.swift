import KeptCore
import SwiftUI

/// A clip drawn in one line, by kind: prose in SF Pro, code in SF Mono, a
/// link as its host and muted path, a color as its swatch, an image as its
/// thumbnail, files as their icon and name. No kind labels. When selected,
/// the highlighter goes behind the text only, never over a glyph.
struct ClipSummary: View {
    let clip: Clip
    let isMarked: Bool
    let resources: PanelResources

    var body: some View {
        switch clip.kind {
        case .text, .richText:
            line(Text(clip.title), isCode: clip.metadata.looksLikeCode)
        case .link:
            let parts = ClipDisplay.linkParts(of: clip.title)
            line(Text(Self.twoTone(parts.host, parts.rest)), isCode: false)
        case .color:
            HStack(spacing: Theme.Spacing.glyphGap) {
                ColorSwatch(hex: clip.metadata.colorHex ?? clip.title, size: Theme.Layout.colorSwatchSize)
                line(Text(clip.title), isCode: true)
            }
        case .image:
            HStack(spacing: Theme.Spacing.glyphGap) {
                RowThumbnail(clip: clip, thumbnails: resources.thumbnails)
                line(Text(clip.title), isCode: false)
            }
        case .file:
            HStack(spacing: Theme.Spacing.glyphGap) {
                Image(nsImage: resources.icons.fileIcon(forName: ClipDisplay.firstFileName(of: clip)))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: Theme.Layout.rowGlyphSize, height: Theme.Layout.rowGlyphSize)
                    .accessibilityHidden(true)
                line(Text(fileText), isCode: false)
            }
        }
    }

    private func line(_ text: Text, isCode: Bool) -> some View {
        text
            .font(isCode ? Theme.Typography.rowCode : Theme.Typography.rowTitle)
            .foregroundStyle(Theme.Colors.ink)
            .lineLimit(1)
            .truncationMode(.tail)
            .marked(isMarked)
    }

    /// "3 files" followed by their names, muted.
    private var fileText: AttributedString {
        let count = clip.metadata.fileCount ?? 1
        return count > 1
            ? Self.twoTone("\(count) files", "  " + clip.title)
            : Self.twoTone(clip.title, "")
    }

    /// `primary` in ink, then `secondary` muted.
    static func twoTone(_ primary: String, _ secondary: String) -> AttributedString {
        typealias Foreground = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
        var first = AttributedString(primary)
        first[Foreground.self] = Theme.Colors.ink
        var second = AttributedString(secondary)
        second[Foreground.self] = Theme.Colors.inkMuted
        return first + second
    }
}

/// A small square of the clip's color, outlined so white and black show.
struct ColorSwatch: View {
    let hex: String
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(hex: hex) ?? .clear)
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Theme.Colors.hairline, lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

/// An image clip's thumbnail, cropped to the row's slot.
private struct RowThumbnail: View {
    let clip: Clip
    let thumbnails: ThumbnailCache
    @State private var image: NSImage?

    var body: some View {
        let size = Theme.Layout.rowThumbnailSize
        let shown = image ?? thumbnails.cachedImage(for: clip, maxPixelSize: ThumbnailCache.rowPixelSize)
        ZStack {
            if let shown {
                Image(nsImage: shown)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Theme.Colors.wash
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Theme.Colors.hairline, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
        .task(id: clip.contentHash) {
            image = await thumbnails.image(for: clip, maxPixelSize: ThumbnailCache.rowPixelSize)
        }
    }
}
