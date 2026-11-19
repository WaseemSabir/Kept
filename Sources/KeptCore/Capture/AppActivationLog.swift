/// Which app was frontmost when, for the last little while.
///
/// Capture polls the pasteboard every half second, so the app in front at
/// the poll isn't always the one that copied: a password manager's
/// quick-access window can copy (without a privacy marker) and hand focus
/// back to the browser before the poll sees the change. The app records
/// every activation here, and capture skips a copy if an excluded app was
/// frontmost at any moment since the previous poll.
///
/// Times are seconds on a monotonic clock (the app uses
/// `ProcessInfo.systemUptime`), so a change of the wall clock can't open or
/// close the window.
public struct AppActivationLog: Sendable, Hashable {
    public struct Activation: Sendable, Hashable {
        /// The app's bundle ID; `nil` for an app without one.
        public var bundleID: String?
        public var time: Double

        public init(bundleID: String?, time: Double) {
            self.bundleID = bundleID
            self.time = time
        }
    }

    /// Activations older than this, measured from the newest, are dropped,
    /// except the last of them (the app that stayed in front after it).
    public static let retention: Double = 120

    /// Activations in time order.
    public private(set) var activations: [Activation] = []

    public init() {}

    /// Notes that `bundleID` became the frontmost app at `time`.
    public mutating func record(_ bundleID: String?, at time: Double) {
        // Notifications arrive in order, but a late one still goes in its place.
        let index = activations.lastIndex { $0.time <= time }.map { $0 + 1 } ?? 0
        activations.insert(Activation(bundleID: bundleID, time: time), at: index)

        guard let newest = activations.last?.time else { return }
        let cutoff = newest - Self.retention
        if let lastBeforeCutoff = activations.lastIndex(where: { $0.time < cutoff }), lastBeforeCutoff > 0 {
            activations.removeFirst(lastBeforeCutoff)
        }
    }

    /// The apps that were frontmost at some moment from `start` through
    /// `end`: the one in front at `start` (when known) and each one
    /// activated after it, in order, without repeats.
    public func frontmostApps(from start: Double, through end: Double) -> [String] {
        let first = activations.lastIndex { $0.time <= start } ?? activations.startIndex
        var apps: [String] = []
        var seen = Set<String>()
        for activation in activations[first...] {
            guard activation.time <= end else { break }
            guard let bundleID = activation.bundleID, seen.insert(bundleID.lowercased()).inserted else { continue }
            apps.append(bundleID)
        }
        return apps
    }

    /// The first app `settings` excludes that was frontmost at some moment
    /// from `start` through `end`; `nil` when none was.
    public func excludedApp(from start: Double, through end: Double, settings: CaptureSettings) -> String? {
        frontmostApps(from: start, through: end).first { settings.excludes(bundleID: $0) }
    }
}
