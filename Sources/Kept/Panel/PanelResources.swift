import Foundation

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
