import KeptCore
import SwiftUI

/// The right pane: the selected clip in full, then its facts.
struct PreviewPane: View {
    let model: PanelViewModel
    let resources: PanelResources

    var body: some View {
        if let clip = model.selectedClip {
            let preview = model.preview(for: clip)
            VStack(alignment: .leading, spacing: 14) {
                PreviewContent(clip: clip, preview: preview, resources: resources)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                FactList(facts: model.facts(for: clip, preview: preview), icons: resources.icons)
            }
            .padding(Theme.Spacing.previewInset)
        } else {
            Color.clear
        }
    }
}

/// The clip itself, drawn by kind.
private struct PreviewContent: View {
    let clip: Clip
    let preview: ClipPreview
    let resources: PanelResources

    var body: some View {
        switch preview.content {
        case .text(let text, let isCode):
            scrolling {
                VStack(alignment: .leading, spacing: 10) {
                    Text(text)
                        .font(isCode ? Theme.Typography.previewCode : Theme.Typography.preview)
                        .foregroundStyle(Theme.Colors.ink)
                        .lineSpacing(isCode ? 3 : 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let total = preview.truncatedFrom {
                        Text("Showing the first \(PreviewLoader.maxCharacters.formatted()) of \(total.formatted()) characters.")
                            .font(Theme.Typography.rowMeta)
                            .foregroundStyle(Theme.Colors.inkMuted)
                    }
                }
            }

        case .link(let url):
            VStack(alignment: .leading, spacing: 6) {
                Text(ClipDisplay.linkParts(of: url).host)
                    .font(Theme.Typography.previewHost)
                    .foregroundStyle(Theme.Colors.ink)
                    .lineLimit(1)
                Text(url)
                    .font(Theme.Typography.previewCode)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .color(let hex, let text):
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: hex) ?? .clear)
                    .frame(height: 120)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Theme.Colors.hairline, lineWidth: 0.5)
                    }
                    .accessibilityHidden(true)
                Text(hex)
                    .font(Theme.Typography.previewValue)
                    .foregroundStyle(Theme.Colors.ink)
                if text.caseInsensitiveCompare(hex) != .orderedSame {
                    Text(text)
                        .font(Theme.Typography.previewCode)
                        .foregroundStyle(Theme.Colors.inkMuted)
                }
            }

        case .image:
            PreviewImage(clip: clip, thumbnails: resources.thumbnails)

        case .files(let paths):
            scrolling {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(paths.prefix(Self.maxFiles).enumerated()), id: \.offset) { _, path in
                        FileEntry(path: path, icons: resources.icons)
                    }
                    if paths.count > Self.maxFiles {
                        Text("And \((paths.count - Self.maxFiles).formatted()) more")
                            .font(Theme.Typography.rowMeta)
                            .foregroundStyle(Theme.Colors.inkMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .unavailable(let message):
            Text(message)
                .font(Theme.Typography.preview)
                .foregroundStyle(Theme.Colors.inkMuted)
        }
    }

    private static let maxFiles = 200

    private func scrolling<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.vertical) {
            content()
        }
        .scrollIndicators(.automatic)
    }
}

/// An image clip fitted to the pane, never scaled past its own size.
private struct PreviewImage: View {
    let clip: Clip
    let thumbnails: ThumbnailCache
    @State private var image: NSImage?

    var body: some View {
        let shown = image ?? thumbnails.cachedImage(for: clip, maxPixelSize: ThumbnailCache.previewPixelSize)
        let pixels = clip.metadata.imagePixelSize
        Group {
            if let shown {
                Image(nsImage: shown)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Theme.Colors.hairline, lineWidth: 0.5)
                    }
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.Colors.wash)
                    .aspectRatio(pixels.map { CGFloat($0.width) / CGFloat(max($0.height, 1)) } ?? 1.6, contentMode: .fit)
            }
        }
        .frame(maxWidth: pixels.map { CGFloat($0.width) }, maxHeight: pixels.map { CGFloat($0.height) })
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel(clip.title)
        .task(id: clip.contentHash) {
            image = await thumbnails.image(for: clip, maxPixelSize: ThumbnailCache.previewPixelSize)
        }
    }
}

/// One file in a file clip: its icon, name and folder.
private struct FileEntry: View {
    let path: String
    let icons: IconCache

    var body: some View {
        let name = (path as NSString).lastPathComponent
        HStack(spacing: 10) {
            Image(nsImage: icons.fileIcon(forName: name))
                .resizable()
                .interpolation(.high)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(Theme.Typography.preview)
                    .foregroundStyle(Theme.Colors.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let folder = ClipDisplay.folder(of: path) {
                    Text(folder)
                        .font(Theme.Typography.previewPath)
                        .foregroundStyle(Theme.Colors.inkMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The facts under the preview, as a two-column label / value list.
private struct FactList: View {
    let facts: [ClipFact]
    let icons: IconCache

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 5) {
            ForEach(facts) { fact in
                GridRow {
                    Text(fact.label)
                        .font(Theme.Typography.factLabel)
                        .foregroundStyle(Theme.Colors.inkMuted)
                        .frame(width: Theme.Layout.factLabelWidth, alignment: .leading)
                    HStack(spacing: 5) {
                        if let bundleID = fact.appBundleID, let icon = icons.appIcon(for: bundleID) {
                            Image(nsImage: icon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 14, height: 14)
                                .accessibilityHidden(true)
                        }
                        Text(fact.value)
                            .font(Theme.Typography.factValue)
                            .foregroundStyle(Theme.Colors.ink)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
