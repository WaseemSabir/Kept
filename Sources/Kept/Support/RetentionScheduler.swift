import Foundation
import KeptCore
import Observation

/// Applies "Forget unpinned clips" (`Preferences.forgetAfter`): at launch,
/// as soon as the setting changes, and then every hour on a tolerant
/// timer, it deletes the unpinned clips last copied or pasted before the
/// cutoff (`HistoryStore.forgetUnpinned(olderThan:)`). Pins always stay.
///
/// The rows go on the main actor, a quick delete; their blob files are
/// deleted on a background queue. With "Never" no timer runs.
@MainActor
final class RetentionScheduler {
    /// How often the history is checked while a period is set.
    static let interval: TimeInterval = 60 * 60
    /// The timer may fire this much late, so it can share a wake-up.
    static let tolerance: TimeInterval = 10 * 60

    private let store: HistoryStore
    private let preferences: Preferences
    private let now: @MainActor () -> Date
    private var timer: Timer?
    private var isObserving = false

    init(store: HistoryStore, preferences: Preferences, now: @escaping @MainActor () -> Date = { Date() }) {
        self.store = store
        self.preferences = preferences
        self.now = now
    }

    /// Whether the hourly check is scheduled (not with "Never").
    var isScheduled: Bool { timer != nil }

    /// Forgets what the setting says now, schedules the hourly check and
    /// follows the setting from here on.
    func start() {
        apply()
        guard !isObserving else { return }
        isObserving = true
        observeSetting()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isObserving = false
    }

    /// Deletes the unpinned clips older than the setting allows. Returns
    /// how many went (none with "Never").
    @discardableResult
    func forgetExpiredClips() -> Int {
        guard let cutoff = preferences.forgetAfter.cutoff(before: now()) else { return 0 }
        do throws(HistoryStoreError) {
            let count = try store.forgetUnpinned(olderThan: cutoff)
            if count > 0 {
                Log.history.info("Forgot \(count, privacy: .public) clips older than the retention period")
            }
            return count
        } catch {
            Log.history.error("Couldn't forget old clips: \(error.description, privacy: .public)")
            return 0
        }
    }

    // MARK: Scheduling

    private func apply() {
        forgetExpiredClips()
        reschedule()
    }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard preferences.forgetAfter != .never else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.forgetExpiredClips()
            }
        }
        timer.tolerance = Self.tolerance
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func observeSetting() {
        withObservationTracking {
            _ = preferences.forgetAfter
        } onChange: { [weak self] in
            let scheduler = self
            Task { @MainActor in
                scheduler?.settingDidChange()
            }
        }
    }

    private func settingDidChange() {
        guard isObserving else { return }
        apply()
        observeSetting()
    }
}
