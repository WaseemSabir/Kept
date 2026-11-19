import Foundation
import Testing
@testable import Kept

@Suite("Age formatter")
struct AgeFormatterTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    private let locale = Locale(identifier: "en_US_POSIX")

    /// Wednesday 18 November 2026, 15:00 UTC.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 15)) ?? Date()
    }

    private func short(_ secondsAgo: TimeInterval) -> String {
        AgeFormatter.shortAge(of: now.addingTimeInterval(-secondsAgo), now: now, calendar: calendar, locale: locale)
    }

    @Test("Short ages in the list")
    func shortAges() {
        #expect(short(5) == "now")
        #expect(short(-30) == "now")
        #expect(short(2 * 60) == "2m")
        #expect(short(59 * 60) == "59m")
        #expect(short(3 * 3600) == "3h")
        #expect(short(14 * 3600) == "14h")
        #expect(short(20 * 3600) == "Yesterday")
        #expect(short(2 * 86400) == "Mon")
        #expect(short(30 * 86400) == "Oct 19")
        #expect(short(400 * 86400) == "Oct 14, 2025")
    }

    @Test("A few hours across midnight still read as hours")
    func hoursAcrossMidnight() {
        let lateLastNight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 23)) ?? now
        let earlyToday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 1)) ?? now
        #expect(AgeFormatter.shortAge(of: lateLastNight, now: earlyToday, calendar: calendar, locale: locale) == "2h")
    }

    @Test("Sentences in the preview")
    func copiedDescriptions() {
        func describe(_ secondsAgo: TimeInterval) -> String {
            AgeFormatter.copiedDescription(
                of: now.addingTimeInterval(-secondsAgo), now: now, calendar: calendar, locale: locale
            )
        }
        #expect(describe(10) == "Just now")
        #expect(describe(60) == "1 minute ago")
        #expect(describe(12 * 60) == "12 minutes ago")
        #expect(describe(3 * 3600).hasPrefix("Today at "))
        #expect(describe(20 * 3600).hasPrefix("Yesterday at "))
        #expect(describe(2 * 86400).hasPrefix("Monday at "))
        #expect(describe(30 * 86400).hasPrefix("Oct 19 at "))
    }
}
