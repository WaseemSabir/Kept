import Foundation
import Testing
@testable import Kept
import KeptCore

@MainActor
@Suite("Retention scheduler")
struct RetentionSchedulerTests {
    let directory: URL
    let suiteName = "app.kept.tests.\(UUID().uuidString)"

    init() throws {
        directory = try makeTemporaryDirectory()
    }

    private func cleanUp() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        removeTemporaryDirectory(directory)
    }

    /// "Now", and a history around it: a pin from 40 days ago, an unpinned
    /// clip from two days ago and one from an hour ago.
    private static let now = Date.at(10_000_000)

    private func makeHarness() throws -> (RetentionScheduler, HistoryStore, Preferences) {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let preferences = Preferences(defaults: defaults)
        let store = try HistoryStore(directory: directory)
        let pin = try store.record(try textDraft("old pin"), at: Self.now.addingTimeInterval(-40 * 86_400))
        try store.pin(pin.id)
        try store.record(try textDraft("two days old"), at: Self.now.addingTimeInterval(-2 * 86_400))
        try store.record(try textDraft("an hour old"), at: Self.now.addingTimeInterval(-3_600))
        let scheduler = RetentionScheduler(store: store, preferences: preferences, now: { Self.now })
        return (scheduler, store, preferences)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<400 where !condition() {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("With Never, nothing is forgotten and no timer runs")
    func neverForgets() throws {
        defer { cleanUp() }
        let (scheduler, store, _) = try makeHarness()
        scheduler.start()
        #expect(!scheduler.isScheduled)
        #expect(scheduler.forgetExpiredClips() == 0)
        #expect(store.recent.count == 2)
        #expect(store.pinned.count == 1)
        scheduler.stop()
    }

    @Test("Forgets at launch, schedules an hourly check, and keeps pins")
    func forgetsAtLaunch() throws {
        defer { cleanUp() }
        let (scheduler, store, preferences) = try makeHarness()
        preferences.forgetAfter = .day
        scheduler.start()
        #expect(scheduler.isScheduled)
        #expect(store.recent.map(\.title) == ["an hour old"])
        #expect(store.pinned.map(\.title) == ["old pin"])
        #expect(RetentionScheduler.interval == 3_600)
        #expect(RetentionScheduler.tolerance > 0)
        scheduler.stop()
        #expect(!scheduler.isScheduled)
    }

    @Test("Applies a new setting at once, and stops checking with Never")
    func followsTheSetting() async throws {
        defer { cleanUp() }
        let (scheduler, store, preferences) = try makeHarness()
        scheduler.start()
        #expect(store.recent.count == 2)

        preferences.forgetAfter = .month
        try await waitUntil { scheduler.isScheduled }
        #expect(scheduler.isScheduled)
        #expect(store.recent.count == 2, "nothing is a month old")

        preferences.forgetAfter = .day
        try await waitUntil { store.recent.count == 1 }
        #expect(store.recent.map(\.title) == ["an hour old"])

        preferences.forgetAfter = .never
        try await waitUntil { !scheduler.isScheduled }
        #expect(!scheduler.isScheduled)
        #expect(store.pinned.count == 1)
        scheduler.stop()
    }

    @Test("Settings names the choices and says what they mean")
    func settingsCopy() {
        #expect(RetentionPeriod.allCases.map { SettingsModel.title(for: $0) } == ["Never", "After a day", "After a week", "After a month"])
    }
}
