/// Where the panel opens.
public enum PanelPosition: String, Sendable, Hashable, CaseIterable {
    /// Centered on the screen with the active window.
    case activeScreenCenter
    /// At the mouse pointer.
    case mouse
    /// Under the menu bar icon.
    case statusItem
}
