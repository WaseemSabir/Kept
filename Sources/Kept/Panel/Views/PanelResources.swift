import SwiftUI

/// The caches the panel's views draw from: app names and icons, file icons,
/// and image thumbnails. Kept apart from `PanelViewModel` so the model holds
/// logic only.
@MainActor
final class PanelResources {
    let icons: IconCache
    let thumbnails: ThumbnailCache

    init(icons: IconCache, thumbnails: ThumbnailCache) {
        self.icons = icons
        self.thumbnails = thumbnails
    }
}

private struct StaticRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Set while rendering with `ImageRenderer`, which can't draw AppKit-backed
    /// views: the search field becomes text and the list doesn't scroll.
    var isStaticRendering: Bool {
        get { self[StaticRenderingKey.self] }
        set { self[StaticRenderingKey.self] = newValue }
    }
}
