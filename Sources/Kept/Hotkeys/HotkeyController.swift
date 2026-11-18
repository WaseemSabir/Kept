import KeyboardShortcuts

/// Listens for Kept's global shortcuts and forwards them to the app.
///
/// `KeyboardShortcuts` registers them with Carbon's `RegisterEventHotKey`,
/// which needs no permission prompt and works in the sandbox.
@MainActor
final class HotkeyController {
    private var listeners: [Task<Void, Never>] = []

    /// Starts listening. `togglePanel` runs each time the open/close
    /// shortcut is pressed.
    func start(togglePanel: @escaping @MainActor () -> Void) {
        stop()
        listeners.append(Task {
            for await event in KeyboardShortcuts.events(for: .togglePanel) where event == .keyDown {
                togglePanel()
            }
        })
    }

    func stop() {
        listeners.forEach { $0.cancel() }
        listeners.removeAll()
    }
}
