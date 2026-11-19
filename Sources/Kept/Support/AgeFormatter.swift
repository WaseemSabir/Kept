import Foundation

/// How long ago a clip was copied, in two lengths: a short age for the list
/// ("now", "2m", "3h", "Yesterday", "Mon", "Mar 12") and a sentence for the
/// preview ("2 minutes ago", "Today at 14:32").
enum AgeFormatter {
    /// Ages within a few hours show hours even across midnight: "2h" says
    /// more than "Yesterday" for something copied at 23:00.
    static let hoursAcrossMidnight = 6

    static func shortAge(
        of date: Date,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if calendar.isDate(date, inSameDayAs: now) || hours < hoursAcrossMidnight {
            return "\(hours)h"
        }
        let days = daysBetween(date, and: now, calendar: calendar)
        if days == 1 { return "Yesterday" }
        let style = formatStyle(calendar: calendar, locale: locale)
        if days < 7 { return date.formatted(style.weekday(.abbreviated)) }
        if isSameYear(date, now, calendar: calendar) {
            return date.formatted(style.day().month(.abbreviated))
        }
        return date.formatted(style.day().month(.abbreviated).year())
    }

    static func copiedDescription(
        of date: Date,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "Just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago" }

        let style = formatStyle(calendar: calendar, locale: locale)
        let time = date.formatted(style.hour().minute())
        let days = daysBetween(date, and: now, calendar: calendar)
        switch days {
        case ...0: return "Today at \(time)"
        case 1: return "Yesterday at \(time)"
        case 2..<7: return "\(date.formatted(style.weekday(.wide))) at \(time)"
        default:
            let day = isSameYear(date, now, calendar: calendar)
                ? date.formatted(style.day().month(.abbreviated))
                : date.formatted(style.day().month(.abbreviated).year())
            return "\(day) at \(time)"
        }
    }

    /// Calendar days from `date` to `now` (0 = same day).
    private static func daysBetween(_ date: Date, and now: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    private static func isSameYear(_ date: Date, _ other: Date, calendar: Calendar) -> Bool {
        calendar.component(.year, from: date) == calendar.component(.year, from: other)
    }

    private static func formatStyle(calendar: Calendar, locale: Locale) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }
}
