#if DEBUG
import AppKit
import KeptCore
import SwiftUI

/// Draws the panel offscreen in sample states and writes PNGs for design
/// review: `Kept --render-snapshots <dir>`.
///
/// Every state renders at 2× in light and dark mode, from a temporary history
/// filled with `SampleHistory`. Vibrancy doesn't draw offscreen, so the panel
/// sits on the opaque window background instead. The copy-only hint renders
/// the same way, as a card on a desktop-gray canvas, and so do the Settings
/// panes (`SettingsSnapshots`).
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
        var options = PasteOptions()
        /// Drawn with the Increase Contrast appearance.
        var increasedContrast = false
        var configure: @MainActor (PanelViewModel) -> Void = { _ in }
    }

    /// The copy-only hint, for one macOS version's wording.
    private struct HintScene {
        let name: String
        let hint: PastePlan.Hint
        var osMajorVersion = 26
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
        Scene(name: "no-results") { $0.query = "zebra" },
        Scene(name: "filter-links") { $0.filter = .links },
        Scene(name: "confirm-clear") { $0.perform(.requestClearUnpinned) },
        Scene(name: "paused", isPaused: true),
        Scene(name: "empty", history: .empty),
        Scene(name: "always-plain-text", options: PasteOptions(alwaysPastePlainText: true)),
        Scene(name: "copy-only-mode", options: PasteOptions(pasteDirectly: false)),
        Scene(name: "search-increased-contrast", increasedContrast: true) { $0.query = "pasteboard" },
        Scene(name: "selected-named") { select($0) { $0.customTitle != nil } },
        Scene(name: "rename") { model in
            select(model) { $0.title.hasPrefix("1 Ferry Building") }
            model.perform(.beginRename)
            model.nameDraft = "Studio address"
        },
        Scene(name: "rename-image") { model in
            select(model) { $0.kind == .image }
            model.perform(.beginRename)
        },
        Scene(name: "edit-text") { model in
            select(model) { $0.title.hasPrefix("Thanks for the quick turnaround") }
            model.perform(.beginTextEdit)
        },
        Scene(name: "edit-code") { model in
            select(model) { $0.metadata.looksLikeCode && $0.title.hasPrefix("func") }
            model.perform(.beginTextEdit)
        },
        Scene(name: "edit-rich-text") { model in
            select(model) { $0.kind == .richText }
            model.perform(.beginTextEdit)
        },
        Scene(name: "edit-image-refused") { model in
            select(model) { $0.kind == .image }
            model.perform(.beginTextEdit)
        },
    ]

    private static let hintScenes: [HintScene] = [
        HintScene(name: "hint-allow-pasting", hint: .allowPasting),
        HintScene(name: "hint-allow-pasting-macos27", hint: .allowPasting, osMajorVersion: 27),
        HintScene(name: "hint-copied", hint: .pressCommandV),
    ]

    private static func select(_ model: PanelViewModel, where matches: (Clip) -> Bool) {
        if let index = model.results.firstIndex(where: matches) {
            model.select(index: index)
        }
    }

    enum Appearance: String, CaseIterable {
        case light
        case dark

        var nsAppearance: NSAppearance? {
            NSAppearance(named: self == .light ? .aqua : .darkAqua)
        }

        var colorScheme: ColorScheme {
            self == .light ? .light : .dark
        }

        /// The same with Increase Contrast on.
        var highContrastAppearance: NSAppearance? {
            NSAppearance(named: self == .light ? .accessibilityHighContrastAqua : .accessibilityHighContrastDarkAqua)
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
        await preload(sample.pinned + sample.recent, into: sampleThumbnails)
        let sampleResources = PanelResources(icons: icons, thumbnails: sampleThumbnails)
        let emptyResources = PanelResources(icons: icons, thumbnails: ThumbnailCache(store: empty))

        var written = 0
        for scene in scenes {
            for appearance in Appearance.allCases {
                let store = scene.history == .sample ? sample : empty
                let isPaused = scene.isPaused
                let options = scene.options
                let model = PanelViewModel(
                    store: store,
                    pasteOptions: { options },
                    appName: { icons.appName(for: $0) },
                    capturePaused: { isPaused }
                )
                model.prepareForShow()
                let size = Theme.Layout.panelSize
                let view = PanelView(model: model, resources: scene.history == .sample ? sampleResources : emptyResources)
                    .frame(width: size.width, height: size.height)
                    .background(Theme.Colors.panelBackground)
                let png = try await renderInWindow(
                    view,
                    size: size,
                    appearance: appearance,
                    increasedContrast: scene.increasedContrast
                ) {
                    // After the search field has taken focus, as if typed.
                    scene.configure(model)
                } afterRender: {
                    // A rename field losing the keyboard as the window
                    // closes would save into the shared sample history.
                    model.cancelEditing()
                }
                try png.write(to: directory.appendingPathComponent("\(scene.name)-\(appearance.rawValue).png"))
                written += 1
            }
        }
        for scene in hintScenes {
            for appearance in Appearance.allCases {
                let png = try await renderInWindow(hintCard(scene), size: nil, appearance: appearance) {}
                try png.write(to: directory.appendingPathComponent("\(scene.name)-\(appearance.rawValue).png"))
                written += 1
            }
        }
        written += try await SettingsSnapshots.render(to: directory, store: sample, icons: icons)
        return written
    }

    /// Decodes every image clip in `clips` at both sizes, so the renders,
    /// which can't wait for async work, find them cached.
    private static func preload(_ clips: [Clip], into thumbnails: ThumbnailCache) async {
        for clip in clips where clip.kind == .image {
            _ = await thumbnails.image(for: clip, maxPixelSize: ThumbnailCache.rowPixelSize)
            _ = await thumbnails.image(for: clip, maxPixelSize: ThumbnailCache.previewPixelSize)
        }
    }

    /// The hint as it floats over an app: an opaque card standing in for
    /// the vibrancy, with margin on a desktop-gray canvas.
    private static func hintCard(_ scene: HintScene) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Layout.hintCornerRadius, style: .continuous)
        return PasteHintView(
            hint: scene.hint,
            permissionDetail: PasteHintCopy.permissionDetail(osMajorVersion: scene.osMajorVersion)
        )
        .background(Theme.Colors.panelBackground, in: shape)
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .padding(28)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    /// Draws `view` in a borderless window that's never shown, with AppKit's
    /// `cacheDisplay`, so AppKit-backed views (the search field, scroll views)
    /// draw as they do on screen. `size` `nil` means the view's own ideal
    /// size. `prepare` runs once the view has appeared; `afterRender` once
    /// it's drawn, before the window closes.
    static func renderInWindow(
        _ view: some View,
        size fixedSize: CGSize?,
        appearance: Appearance,
        increasedContrast: Bool = false,
        prepare: () -> Void,
        afterRender: () -> Void = {}
    ) async throws -> Data {
        // The high-contrast appearance draws system colors stronger; Kept's
        // own tokens follow `forcesIncreasedContrast`.
        let root = view
            .environment(\.colorScheme, appearance.colorScheme)
            .environment(\.forcesIncreasedContrast, increasedContrast)
        let hostingView = NSHostingView(rootView: root)
        let size = fixedSize ?? {
            let fitting = hostingView.fittingSize
            return CGSize(width: fitting.width.rounded(.up), height: fitting.height.rounded(.up))
        }()
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = increasedContrast ? appearance.highContrastAppearance : appearance.nsAppearance
        window.contentView = hostingView
        defer { window.close() }

        hostingView.layoutSubtreeIfNeeded()
        // Let SwiftUI settle (layout passes, `onAppear`, focus), then set the
        // scene up and let it settle again.
        try await Task.sleep(for: .milliseconds(150))
        prepare()
        try await Task.sleep(for: .milliseconds(250))
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()
        let data = try png(of: hostingView)
        afterRender()
        return data
    }

    /// `view` and its subviews drawn at 2× with `cacheDisplay`, as PNG data.
    static func png(of view: NSView) throws -> Data {
        let size = view.bounds.size
        guard size.width > 0, size.height > 0, let bitmap = NSBitmapImageRep(
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
        ) else { throw RenderError(description: "No bitmap for a \(size.width) × \(size.height) render") }
        bitmap.size = size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw RenderError(description: "Couldn't encode the render")
        }
        return png
    }

    struct RenderError: Error, CustomStringConvertible {
        let description: String
    }
}
#endif
