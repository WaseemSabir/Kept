import AppKit
import KeptCore
import SwiftUI

/// Draws the panel offscreen in sample states and writes PNGs for design
/// review: `Kept --render-snapshots <dir>`.
///
/// Every state renders at 2× in light and dark mode, from a temporary history
/// filled with `SampleHistory`. Vibrancy doesn't draw offscreen, so the panel
/// sits on the opaque window background instead.
@MainActor
enum SnapshotRenderer {
    static let flag = "--render-snapshots"

    /// The folder after `--render-snapshots`, or `nil` when the flag isn't
    /// there.
    static func outputDirectory(from arguments: [String]) -> URL? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let next = arguments.index(after: index)
        let path = next < arguments.endIndex ? arguments[next] : "Snapshots"
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Renders every scene and returns the process exit status.
    static func run(writingTo directory: URL) async -> Int32 {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeptSnapshots-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let written = try await render(to: directory, workspace: workspace)
            print("Wrote \(written) snapshots to \(directory.path)")
            return 0
        } catch {
            FileHandle.standardError.write(Data("Couldn't render snapshots: \(error)\n".utf8))
            return 1
        }
    }

    // MARK: Scenes

    private struct Scene {
        let name: String
        var history: History = .sample
        var isPaused = false
        var configure: @MainActor (PanelViewModel) -> Void = { _ in }
    }

    private enum History {
        case sample
        case empty
    }

    private static let scenes: [Scene] = [
        Scene(name: "history"),
        Scene(name: "selected-code") { select($0) { $0.metadata.looksLikeCode && $0.title.hasPrefix("func") } },
        Scene(name: "selected-link") { select($0) { $0.kind == .link } },
        Scene(name: "selected-image") { select($0) { $0.kind == .image } },
        Scene(name: "selected-files") { select($0) { ($0.metadata.fileCount ?? 0) > 1 } },
        Scene(name: "selected-color") { select($0) { $0.kind == .color } },
        Scene(name: "selected-rich-text") { select($0) { $0.kind == .richText } },
        Scene(name: "search") { $0.query = "pasteboard" },
        Scene(name: "no-results") { $0.query = "kubernetes" },
        Scene(name: "filter-links") { $0.filter = .links },
        Scene(name: "confirm-clear") { $0.perform(.requestClearUnpinned) },
        Scene(name: "paused", isPaused: true),
        Scene(name: "empty", history: .empty),
    ]

    private static func select(_ model: PanelViewModel, where matches: (Clip) -> Bool) {
        if let index = model.results.firstIndex(where: matches) {
            model.select(index: index)
        }
    }

    private enum Appearance: String, CaseIterable {
        case light
        case dark

        var nsAppearance: NSAppearance? {
            NSAppearance(named: self == .light ? .aqua : .darkAqua)
        }

        var colorScheme: ColorScheme {
            self == .light ? .light : .dark
        }
    }

    // MARK: Rendering

    private static func render(to directory: URL, workspace: URL) async throws -> Int {
        let now = Date()
        let sample = try HistoryStore(directory: workspace.appendingPathComponent("Sample", isDirectory: true))
        try SampleHistory.fill(sample, now: now)
        let empty = try HistoryStore(directory: workspace.appendingPathComponent("Empty", isDirectory: true))

        let icons = IconCache()
        let sampleThumbnails = ThumbnailCache(store: sample)
        await sampleThumbnails.preload(sample.pinned + sample.recent)
        let sampleResources = PanelResources(icons: icons, thumbnails: sampleThumbnails)
        let emptyResources = PanelResources(icons: icons, thumbnails: ThumbnailCache(store: empty))

        let staticDirectory = directory.appendingPathComponent("static", isDirectory: true)
        try FileManager.default.createDirectory(at: staticDirectory, withIntermediateDirectories: true)

        var written = 0
        for scene in scenes {
            for appearance in Appearance.allCases {
                let store = scene.history == .sample ? sample : empty
                let isPaused = scene.isPaused
                let model = PanelViewModel(
                    store: store,
                    appName: { icons.appName(for: $0) },
                    capturePaused: { isPaused }
                )
                model.prepareForShow()
                scene.configure(model)
                let view = PanelView(model: model, resources: scene.history == .sample ? sampleResources : emptyResources)
                let fileName = "\(scene.name)-\(appearance.rawValue).png"

                let png = try await renderInWindow(view, appearance: appearance)
                try png.write(to: directory.appendingPathComponent(fileName))
                let staticPNG = try renderStatically(view, appearance: appearance)
                try staticPNG.write(to: staticDirectory.appendingPathComponent(fileName))
                written += 2
            }
        }
        return written
    }

    /// Draws `view` in a borderless window that's never shown, with AppKit's
    /// `cacheDisplay`, so AppKit-backed views (the search field, scroll views)
    /// draw as they do on screen.
    private static func renderInWindow(_ view: PanelView, appearance: Appearance) async throws -> Data {
        let size = Theme.Layout.panelSize
        let root = view
            .frame(width: size.width, height: size.height)
            .background(Theme.Colors.panelBackground)
            .environment(\.colorScheme, appearance.colorScheme)
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = appearance.nsAppearance
        window.contentView = hostingView
        defer { window.close() }

        hostingView.layoutSubtreeIfNeeded()
        // Let SwiftUI settle: layout passes, `onAppear`, cached thumbnails.
        try await Task.sleep(for: .milliseconds(250))
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw RenderError(description: "No bitmap for the window render") }
        bitmap.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw RenderError(description: "Couldn't encode the window render")
        }
        return png
    }

    /// Draws `view` with SwiftUI's `ImageRenderer`, which can't draw
    /// AppKit-backed views, so the search field and lists render statically.
    private static func renderStatically(_ view: PanelView, appearance: Appearance) throws -> Data {
        let size = Theme.Layout.panelSize
        let root = view
            .frame(width: size.width, height: size.height)
            .background(Theme.Colors.panelBackground)
            .environment(\.colorScheme, appearance.colorScheme)
            .environment(\.isStaticRendering, true)
        let renderer = ImageRenderer(content: root)
        renderer.scale = 2
        guard let image = renderer.cgImage, let png = ImageTranscoder.pngData(from: image) else {
            throw RenderError(description: "Couldn't render statically")
        }
        return png
    }

    private struct RenderError: Error, CustomStringConvertible {
        let description: String
    }
}
