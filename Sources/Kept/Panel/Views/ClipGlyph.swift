import KeptCore
import SwiftUI

/// What stands before a clip's text in a row: a color's swatch, an
/// image's thumbnail, a file's icon. Text and links have none
/// (`shows(_:)`).
struct ClipGlyph: View {
    let clip: Clip
    let resources: PanelResources

    static func shows(_ clip: Clip) -> Bool {
        switch clip.kind {
        case .color, .image, .file: true
        case .text, .richText, .link: false
        }
    }

    var body: some View {
        switch clip.kind {
        case .color:
            ColorSwatch(hex: clip.metadata.colorHex ?? clip.title, size: Theme.Layout.colorSwatchSize)
        case .image:
            RowThumbnail(clip: clip, thumbnails: resources.thumbnails)
        case .file:
            Image(nsImage: resources.icons.fileIcon(forName: ClipDisplay.firstFileName(of: clip)))
                .resizable()
                .interpolation(.high)
                .frame(width: Theme.Layout.rowGlyphSize, height: Theme.Layout.rowGlyphSize)
                .accessibilityHidden(true)
        case .text, .richText, .link:
            EmptyView()
        }
    }
}

/// A small square of the clip's color, outlined so white and black show.
private struct ColorSwatch: View {
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
