import KeyboardShortcuts

/// Listens for Kept's global shortcuts and forwards them to the app.
///
/// `KeyboardShortcuts` registers them with Carbon's `RegisterEventHotKey`,
/// which needs no permission prompt and works in the sandbox. Shortcuts
/// without a key (the default for all but the panel's) never fire.
@MainActor
final class HotkeyController {
    private var listeners: [Task<Void, Never>] = []

    /// Starts listening.
    /// - Parameters:
    ///   - togglePanel: the open/close shortcut (⇧⌘V by default).
    ///   - pastePlainText: "Paste clipboard as plain text".
    ///   - togglePause: "Pause / resume capture".
    func start(
        togglePanel: @escaping @MainActor () -> Void,
        pastePlainText: @escaping @MainActor () -> Void,
        togglePause: @escaping @MainActor () -> Void
    ) {
        stop()
        listen(for: .togglePanel, togglePanel)
        listen(for: .pastePlainText, pastePlainText)
        listen(for: .togglePause, togglePause)
    }

    func stop() {
        listeners.forEach { $0.cancel() }
        listeners.removeAll()
    }

    private func listen(for name: KeyboardShortcuts.Name, _ action: @escaping @MainActor () -> Void) {
        listeners.append(Task {
            for await event in KeyboardShortcuts.events(for: name) where event == .keyDown {
                action()
            }
        })
    }
}
