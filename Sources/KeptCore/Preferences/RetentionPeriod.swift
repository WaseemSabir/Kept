import Foundation

/// How long an unpinned clip stays after it was last copied or pasted
/// ("Forget unpinned clips" in Settings › Privacy). Pins always stay.
public enum RetentionPeriod: String, Sendable, Hashable, CaseIterable {
    case never
    case day
    case week
    case month

    /// How long a clip is kept, or `nil` for as long as the history has
    /// room. A month is 30 days.
    public var duration: TimeInterval? {
        switch self {
        case .never: nil
        case .day: 24 * 60 * 60
        case .week: 7 * 24 * 60 * 60
        case .month: 30 * 24 * 60 * 60
        }
    }

    /// Unpinned clips last copied before this are forgotten at `now`;
    /// `nil` for `.never`.
    public func cutoff(before now: Date) -> Date? {
        duration.map { now.addingTimeInterval(-$0) }
    }
}
