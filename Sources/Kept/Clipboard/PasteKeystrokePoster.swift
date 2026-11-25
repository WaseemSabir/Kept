import CoreGraphics

/// Posts ⌘V with `CGEvent`, the way Maccy and Clipy do:
/// a combined-session event source that holds back the user's own
/// keys and mouse moves for the moment the shortcut is in flight, key down
/// and up with ⌘ (and the left-⌘ device bit, as a real key press carries),
/// posted to the session event tap.
///
/// Needs the PostEvent permission; without it macOS drops the events
/// silently, so `PasteService` checks first.
@MainActor
final class PasteKeystrokePoster: KeystrokePosting {
    /// `NX_DEVICELCMDKEYMASK`: some apps ignore ⌘ without the device bit.
    static let leftCommandDeviceFlag: UInt64 = 0x08

    private let layout: KeyboardLayout
    private let delay: Duration

    /// - Parameter delay: how long to wait after the call, so the panel has
    ///   ordered out and the app the user was typing in has its key window
    ///   back before the shortcut arrives.
    init(layout: KeyboardLayout, delay: Duration = .milliseconds(50)) {
        self.layout = layout
        self.delay = delay
    }

    func postPasteShortcut() {
        let keyCode = layout.pasteKeyCode
        let delay = delay
        Task {
            try? await Task.sleep(for: delay)
            if !Self.post(commandWith: keyCode) {
                Log.paste.error("Couldn't create the ⌘V key events.")
            }
        }
    }

    /// Posts key down and key up for `keyCode` with ⌘. Returns `false` if
    /// the events couldn't be created.
    static func post(commandWith keyCode: CGKeyCode) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }
        let flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | leftCommandDeviceFlag)
        down.flags = flags
        up.flags = flags
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
    }
}
