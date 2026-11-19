#if DEBUG
import AppKit
import KeptCore
import SwiftUI

/// The Settings panes for `SnapshotRenderer`: each pane on its own, light
/// and dark, the welcome window's content, plus the whole Settings window
/// (title bar and toolbar) on General, in light mode only: offscreen, the
/// selected toolbar item's glass draws as a white block in dark mode, which
/// isn't what users see.
///
/// Settings read a throwaway preferences domain, the sample history and
/// stand-ins for the login item, the paste permission and the dialogs, so
/// rendering never touches the user's settings or System Settings.
@MainActor
enum SettingsSnapshots {
    private struct Scene {
        let name: String
        let pane: SettingsPane
        var loginStatus = LoginItemStatus.notRegistered
        var canPostEvents = true
        var pasteboardAccess = PasteboardAccess.allowed
        var configure: @MainActor (Preferences) -> Void = { _ in }
    }

    private static let scenes: [Scene] = [
        Scene(name: "settings-general", pane: .general, loginStatus: .enabled),
        Scene(name: "settings-general-attention", pane: .general, loginStatus: .requiresApproval, canPostEvents: false),
        Scene(name: "settings-shortcuts", pane: .shortcuts),
        Scene(name: "settings-privacy", pane: .privacy) { preferences in
            preferences.excludeApp("com.apple.TextEdit")
        },
        Scene(name: "settings-privacy-clipboard-access", pane: .privacy, pasteboardAccess: .asks),
        Scene(name: "settings-privacy-forget-week", pane: .privacy) { preferences in
            preferences.forgetAfter = .week
        },
        Scene(name: "settings-about", pane: .about),
    ]

    /// The welcome window, as at a first launch, and with clipboard access
    /// denied (macOS 15.4+).
    private static let welcomeScenes: [Scene] = [
        Scene(name: "welcome", pane: .general),
        Scene(name: "welcome-clipboard-denied", pane: .general, pasteboardAccess: .denied),
    ]

    /// Renders every scene into `directory`; returns how many files it wrote.
    static func render(to directory: URL, store: HistoryStore, icons: IconCache) async throws -> Int {
        var written = 0
        for scene in scenes {
            for appearance in SnapshotRenderer.Appearance.allCases {
                let png = try await withSettings(scene, store: store, icons: icons) { model, _ in
                    let view = SettingsPaneView(pane: scene.pane, model: model)
                        .background(Color(nsColor: .windowBackgroundColor))
                    return try await SnapshotRenderer.renderInWindow(view, size: nil, appearance: appearance) {}
                }
                try png.write(to: directory.appendingPathComponent("\(scene.name)-\(appearance.rawValue).png"))
                written += 1
            }
        }

        for scene in welcomeScenes {
            for appearance in SnapshotRenderer.Appearance.allCases {
                let png = try await withSettings(scene, store: store, icons: icons) { model, _ in
                    let view = WelcomeView(settings: model, shortcut: "⇧⌘V")
                        .background(Color(nsColor: .windowBackgroundColor))
                    return try await SnapshotRenderer.renderInWindow(view, size: nil, appearance: appearance) {}
                }
                try png.write(to: directory.appendingPathComponent("\(scene.name)-\(appearance.rawValue).png"))
                written += 1
            }
        }

        // The real window, toolbar and all. Best effort: a window that
        // can't be drawn offscreen shouldn't cost the pane renders.
        for appearance in [SnapshotRenderer.Appearance.light] {
            do {
                let png = try await withSettings(scenes[0], store: store, icons: icons) { model, defaults in
                    try await renderWindow(model: model, defaults: defaults, appearance: appearance)
                }
                try png.write(to: directory.appendingPathComponent("settings-window-\(appearance.rawValue).png"))
                written += 1
            } catch {
                Log.snapshots.error("Couldn't render the Settings window: \(String(describing: error), privacy: .public)")
                FileHandle.standardError.write(Data("Skipped the Settings window render: \(error)\n".utf8))
            }
        }
        return written
    }

    /// Runs `body` with a Settings model for `scene` on a throwaway
    /// preferences domain, removed afterwards.
    private static func withSettings(
        _ scene: Scene,
        store: HistoryStore,
        icons: IconCache,
        _ body: @MainActor (SettingsModel, UserDefaults) async throws -> Data
    ) async throws -> Data {
        let suiteName = "app.kept.Kept.snapshots.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw SnapshotRenderer.RenderError(description: "No preferences domain for the Settings snapshots")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = Preferences(defaults: defaults)
        scene.configure(preferences)
        let model = SettingsModel(
            preferences: preferences,
            store: store,
            loginItem: StaticLoginItem(status: scene.loginStatus),
            permission: StaticPermission(canPostEvents: scene.canPostEvents),
            onboarding: PasteOnboarding(defaults: defaults),
            dialogs: NoDialogs(),
            icons: icons,
            about: AboutInfo(version: repositoryVersion ?? "0.1.0", build: "128"),
            appIcon: repositoryIcon ?? NSApplication.shared.applicationIconImage ?? NSImage(),
            pasteboard: StaticPasteboardAccess(access: scene.pasteboardAccess),
            menuBarIcon: MenuBarIconPreference(defaults: defaults)
        )
        // The default shortcut, whatever this machine has recorded.
        model.openShortcut = { "⇧⌘V" }
        model.osMajorVersion = 26
        return try await body(model, defaults)
    }

    /// The Settings window as it opens on General, drawn with its title bar
    /// and toolbar. It's ordered in (not shown to anyone on CI) so AppKit
    /// builds the toolbar, then drawn like the panes.
    private static func renderWindow(
        model: SettingsModel,
        defaults: UserDefaults,
        appearance: SnapshotRenderer.Appearance
    ) async throws -> Data {
        let controller = SettingsWindowController(model: model, dialogs: SettingsDialogs(), defaults: defaults)
        let window = controller.prepareWindow(pane: .general)
        window.appearance = appearance.nsAppearance
        window.alphaValue = 0
        window.orderFrontRegardless()
        defer {
            // Not a real close: nothing to hand focus back to.
            window.delegate = nil
            window.close()
        }

        try await Task.sleep(for: .milliseconds(400))
        controller.prepareWindow(pane: .general)
        try await Task.sleep(for: .milliseconds(200))
        guard let frameView = window.contentView?.superview else {
            throw SnapshotRenderer.RenderError(description: "The Settings window has no frame view")
        }
        frameView.layoutSubtreeIfNeeded()
        frameView.displayIfNeeded()
        return try SnapshotRenderer.png(of: frameView)
    }

    // MARK: From the repository

    /// The app icon from `Resources/`, when run from the repository (CI
    /// does); the bare binary has no icon of its own.
    private static var repositoryIcon: NSImage? {
        NSImage(contentsOfFile: "Resources/AppIcon.icns")
    }

    /// The version in `Resources/Info.plist`, when run from the repository.
    private static var repositoryVersion: String? {
        let url = URL(fileURLWithPath: "Resources/Info.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist["CFBundleShortVersionString"] as? String
    }
}

// MARK: Stand-ins

@MainActor
private final class StaticLoginItem: LoginItemControlling {
    let status: LoginItemStatus

    init(status: LoginItemStatus) {
        self.status = status
    }

    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
}

@MainActor
private final class StaticPermission: PermissionChecking {
    let canPostEvents: Bool

    init(canPostEvents: Bool) {
        self.canPostEvents = canPostEvents
    }

    func requestAccess() {}
    func openSettings() {}
}

@MainActor
private final class StaticPasteboardAccess: PasteboardAccessChecking {
    let access: PasteboardAccess

    init(access: PasteboardAccess) {
        self.access = access
    }

    func openSettings() {}
}

@MainActor
private final class NoDialogs: SettingsDialogPresenting {
    func chooseApplications() async -> [URL] { [] }
    func confirmClearHistory(_ prompt: ClearHistoryPrompt) async -> ClearHistoryChoice? { nil }
}
#endif
