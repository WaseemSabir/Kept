/// Bounds on what `HistoryStore` keeps.
public struct HistoryLimits: Sendable, Hashable {
    /// Unpinned clips kept; the oldest beyond this are pruned. Pins are exempt.
    public var historyLimit: Int
    /// Representations larger than this many bytes go to blob files instead
    /// of the database.
    public var inlineThreshold: Int

    /// The default `inlineThreshold`. `ClipBuilder` pre-hashes
    /// representations above it, since they become blob files.
    public static let defaultInlineThreshold = 64 * 1024

    public init(
        historyLimit: Int = PreferenceDefaults.historyLimit,
        inlineThreshold: Int = HistoryLimits.defaultInlineThreshold
    ) {
        self.historyLimit = historyLimit
        self.inlineThreshold = inlineThreshold
    }
}
