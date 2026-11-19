import AppKit
import UniformTypeIdentifiers

/// Source app names and icons by bundle ID, and file icons by type, looked
/// up once and kept for the life of the app.
///
/// File icons come from the file's type (its extension), not the file, so
/// they need no file access and work for files that have since moved.
@MainActor
final class IconCache {
    private struct App {
        let name: String?
        let icon: NSImage?
    }

    private var apps: [String: App] = [:]
    private var fileIcons: [String: NSImage] = [:]

    /// The app's display name, e.g. "Safari"; `nil` when it isn't installed.
    func appName(for bundleID: String) -> String? {
        app(for: bundleID).name
    }

    func appIcon(for bundleID: String) -> NSImage? {
        app(for: bundleID).icon
    }

    /// The icon for a file named `name`; names without an extension get the
    /// folder icon.
    func fileIcon(forName name: String) -> NSImage {
        let fileExtension = (name as NSString).pathExtension.lowercased()
        if let cached = fileIcons[fileExtension] { return cached }
        let type = fileExtension.isEmpty ? UTType.folder : (UTType(filenameExtension: fileExtension) ?? .data)
        let icon = NSWorkspace.shared.icon(for: type)
        fileIcons[fileExtension] = icon
        return icon
    }

    private func app(for bundleID: String) -> App {
        if let cached = apps[bundleID] { return cached }
        let app: App
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            app = App(name: Self.displayName(ofAppAt: url), icon: NSWorkspace.shared.icon(forFile: url.path))
        } else {
            app = App(name: nil, icon: nil)
        }
        apps[bundleID] = app
        return app
    }

    /// The app's own name ("Xcode"), localized when it has one, rather than
    /// its file name, which may have been renamed ("Xcode_26.6").
    private static func displayName(ofAppAt url: URL) -> String {
        let bundle = Bundle(url: url)
        let keys = ["CFBundleDisplayName", "CFBundleName"]
        for dictionary in [bundle?.localizedInfoDictionary, bundle?.infoDictionary] {
            for key in keys {
                if let name = dictionary?[key] as? String, !name.isEmpty { return name }
            }
        }
        let fileName = FileManager.default.displayName(atPath: url.path)
        return fileName.hasSuffix(".app") ? String(fileName.dropLast(4)) : fileName
    }
}
