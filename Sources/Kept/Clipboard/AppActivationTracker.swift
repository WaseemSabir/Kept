import AppKit
import KeptCore

/// Keeps an `AppActivationLog` from `NSWorkspace`'s activation
/// notifications, so capture can tell every app that was frontmost between
/// two polls, not only the one in front at the poll.
///
/// Created once by `AppEnvironment` and kept for the life of the app, so
/// its observer is never removed.
@MainActor
final class AppActivationTracker {
    private(set) var log = AppActivationLog()
    private var observer: (any NSObjectProtocol)?

    /// Seconds on the log's clock: time since the Mac started, which the
    /// wall clock changing (or the user setting it) doesn't move.
    nonisolated static func now() -> Double {
        ProcessInfo.processInfo.systemUptime
    }

    /// - Parameter workspace: whose activations to follow; `nil` follows
    ///   none, and tests call `record(_:at:)` instead.
    init(workspace: NSWorkspace? = .shared) {
        guard let workspace else { return }
        log.record(workspace.frontmostApplication?.bundleIdentifier, at: Self.now())
        observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            let time = Self.now()
            MainActor.assumeIsolated {
                self?.record(bundleID, at: time)
            }
        }
    }

    /// Notes that `bundleID` became the frontmost app at `time` (`now()`).
    func record(_ bundleID: String?, at time: Double) {
        log.record(bundleID, at: time)
    }
}
