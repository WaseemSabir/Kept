import AppKit
import KeptCore

/// The composition root: creates Kept's long-lived objects once and wires
/// them together. Nothing else creates controllers or reaches for singletons.
@MainActor
final class AppEnvironment {
    let preferences: Preferences
    /// `nil` when the history couldn't be opened; the panel then explains
    /// why, and nothing is captured.
    let history: HistoryStore?
    let panelController: PanelController
    private let monitor: PasteboardMonitor
    private let captureService: CaptureService?
    /// `nil` when the history couldn't be opened.
    private let pasteService: PasteService?
    private let hintController: PasteHintController
    private let statusItemController: StatusItemController
    private let hotkeyController: HotkeyController

    init() {
        let preferences = Preferences()
        self.preferences = preferences

        let opened = Self.openHistory(historyLimit: preferences.historyLimit)
        history = opened.store

        let monitor = PasteboardMonitor(isPaused: { preferences.isPaused })
        self.monitor = monitor
        let icons = IconCache()
        let resources = PanelResources(icons: icons, thumbnails: ThumbnailCache(store: opened.store))

        let permission = PostEventPermission()
        let hintController = PasteHintController(openSettings: { permission.openSettings() })
        self.hintController = hintController
        let pasteService: PasteService?
        if let store = opened.store {
            captureService = CaptureService(store: store, settings: { preferences.captureSettings })
            pasteService = PasteService(
                store: store,
                writer: PasteboardWriter(),
                monitor: monitor,
                options: { preferences.pasteOptions },
                permission: permission,
                poster: PasteKeystrokePoster(layout: KeyboardLayout()),
                focus: SystemKeyboardFocus(),
                onboarding: PasteOnboarding(),
                hints: hintController
            )
        } else {
            captureService = nil
            pasteService = nil
        }
        self.pasteService = pasteService

        let model = PanelViewModel(
            store: opened.store,
            unavailableReason: opened.failure,
            paster: pasteService,
            pasteOptions: { preferences.pasteOptions },
            appName: { icons.appName(for: $0) },
            capturePaused: { preferences.isPaused }
        )
        let panelController = PanelController(model: model, resources: resources)
        panelController.willShow = { [hintController] in hintController.dismiss() }
        self.panelController = panelController
        statusItemController = StatusItemController(togglePanel: { [panelController] in panelController.toggle() })
        hotkeyController = HotkeyController()
    }

    /// Starts listening for Kept's global shortcuts and for copies.
    func start() {
        hotkeyController.start(
            togglePanel: { [panelController] in panelController.toggle() },
            pastePlainText: { [weak self] in self?.pasteClipboardAsPlainText() },
            togglePause: { [preferences] in preferences.isPaused.toggle() }
        )
        if let captureService {
            monitor.onChange = { _ in captureService.captureCurrentContents() }
            monitor.start()
        }
        observeHistoryLimit()
        observePause()
    }

    // MARK: Shortcuts

    /// "Paste clipboard as plain text": the panel goes away first, so ⌘V
    /// reaches the app underneath. A beep when there's no text to paste.
    private func pasteClipboardAsPlainText() {
        panelController.hide()
        guard pasteService?.pasteClipboardAsPlainText() != nil else {
            NSSound.beep()
            return
        }
    }

    /// Keeps the menu bar glyph in step with pausing, from the shortcut or
    /// anywhere else.
    private func observePause() {
        statusItemController.setPaused(preferences.isPaused)
        withObservationTracking {
            _ = preferences.isPaused
        } onChange: { [weak self] in
            let environment = self
            Task { @MainActor in
                environment?.observePause()
            }
        }
    }

    // MARK: History

    /// Opens the history in `Application Support/Kept` (inside the sandbox
    /// container). On failure, returns a sentence for the panel to show; the
    /// details go to the log.
    private static func openHistory(historyLimit: Int) -> (store: HistoryStore?, failure: String?) {
        let directory: URL
        do {
            directory = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Kept", isDirectory: true)
        } catch {
            Log.history.error("No Application Support folder: \(String(describing: error), privacy: .public)")
            return (nil, "Kept couldn't find its Application Support folder.")
        }

        do throws(HistoryStoreError) {
            let store = try HistoryStore(directory: directory, limits: HistoryLimits(historyLimit: historyLimit))
            return (store, nil)
        } catch {
            Log.history.error("Couldn't open the history: \(error.description, privacy: .public)")
            if case .newerSchema = error {
                return (nil, "Your history was saved by a newer version of Kept.")
            }
            return (nil, "The history file couldn't be read.")
        }
    }

    /// Applies the history size from Preferences whenever it changes; the
    /// store prunes unpinned clips past it.
    private func observeHistoryLimit() {
        guard history != nil else { return }
        withObservationTracking {
            _ = preferences.historyLimit
        } onChange: { [weak self] in
            let environment = self
            Task { @MainActor in
                environment?.historyLimitDidChange()
            }
        }
    }

    private func historyLimitDidChange() {
        do throws(HistoryStoreError) {
            try history?.setHistoryLimit(preferences.historyLimit)
        } catch {
            Log.history.error("Couldn't apply the history size: \(error.description, privacy: .public)")
        }
        observeHistoryLimit()
    }
}
