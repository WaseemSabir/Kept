import AppKit

/// Watches the pasteboard for new copies.
///
/// macOS has no pasteboard-change notification, so the monitor polls
/// `changeCount` on the main run loop and reports real changes to
/// `onChange`. It skips Kept's own writes (by the change counts the writer
/// reports), one change after `ignoreNextCopy()`, and everything while
/// capture is paused. It never reads pasteboard contents itself.
@MainActor
final class PasteboardMonitor {
    /// What one poll found.
    enum Outcome: Equatable {
        case unchanged
        /// Kept wrote this change itself.
        case ownWrite
        case paused
        /// Skipped because of `ignoreNextCopy()`.
        case ignoredOnce
        /// Reported to `onChange`.
        case changed(changeCount: Int)
    }

    static let interval: TimeInterval = 0.5
    static let tolerance: TimeInterval = 0.15

    /// Called on the main actor with the new change count for each change
    /// worth reading.
    var onChange: (@MainActor (Int) -> Void)?
    /// Whether the next change will be skipped.
    private(set) var isIgnoringNextCopy = false
    /// When the poll before the latest one ran (`AppActivationTracker.now()`
    /// time). While `onChange` runs, the change it reports was made after
    /// this, so capture checks every app that was in front since then.
    private(set) var previousPollTime: Double?

    private let pasteboard: NSPasteboard
    private let isPaused: @MainActor () -> Bool
    private var lastChangeCount: Int
    private var lastPollTime: Double?
    private var ownChangeCounts: Set<Int> = []
    private var timer: Timer?

    init(pasteboard: NSPasteboard = .general, isPaused: @escaping @MainActor () -> Bool) {
        self.pasteboard = pasteboard
        self.isPaused = isPaused
        // Whatever is on the pasteboard at launch was copied before Kept ran.
        lastChangeCount = pasteboard.changeCount
    }

    /// Starts polling. Changes made while the monitor was stopped are skipped.
    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        lastPollTime = AppActivationTracker.now()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.poll()
            }
        }
        timer.tolerance = Self.tolerance
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Skips the next pasteboard change, e.g. before copying a password by hand.
    func ignoreNextCopy() {
        isIgnoringNextCopy = true
    }

    /// Takes back `ignoreNextCopy()` before a copy used it up.
    func cancelIgnoreNextCopy() {
        isIgnoringNextCopy = false
    }

    /// Records that Kept itself wrote the pasteboard and it now has `changeCount`.
    func noteOwnWrite(changeCount: Int) {
        ownChangeCounts.insert(changeCount)
    }

    /// Checks the pasteboard once. The timer calls this; tests call it directly.
    @discardableResult
    func poll() -> Outcome {
        let now = AppActivationTracker.now()
        previousPollTime = lastPollTime ?? now
        lastPollTime = now
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return .unchanged }
        lastChangeCount = changeCount

        let isOwnWrite = ownChangeCounts.contains(changeCount)
        // Older own writes were overwritten before a poll saw them.
        ownChangeCounts = ownChangeCounts.filter { $0 > changeCount }
        if isOwnWrite { return .ownWrite }
        if isPaused() { return .paused }
        if isIgnoringNextCopy {
            isIgnoringNextCopy = false
            return .ignoredOnce
        }
        onChange?(changeCount)
        return .changed(changeCount: changeCount)
    }
}
