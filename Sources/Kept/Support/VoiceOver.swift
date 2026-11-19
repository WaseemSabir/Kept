import AppKit

/// Tells VoiceOver users about something without moving the keyboard focus:
/// the panel's selection, which moves while the search field keeps the
/// keyboard, and the copy-only hint, which never takes it.
@MainActor
enum VoiceOver {
    /// Asks VoiceOver to read `message` now, ahead of what it was reading.
    static func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}
