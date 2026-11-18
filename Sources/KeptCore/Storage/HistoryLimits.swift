/// Bounds on what `HistoryStore` keeps.
public struct HistoryLimits: Sendable, Hashable {
    /// Unpinned clips kept; the oldest beyond this are pruned. Pins are exempt.
    public var historyLimit: Int
    /// Representations larger than this many bytes go to blob files instead
    /// of the database.
    public var inlineThreshold: Int

    public init(
        historyLimit: Int = PreferenceDefaults.historyLimit,
        inlineThreshold: Int = 64 * 1024
    ) {
        self.historyLimit = historyLimit
        self.inlineThreshold = inlineThreshold
    }
}
