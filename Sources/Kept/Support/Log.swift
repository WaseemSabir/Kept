import os

/// Kept's loggers, one per area. Read them in Console.app by filtering on
/// the subsystem `app.kept.Kept`.
enum Log {
    static let subsystem = "app.kept.Kept"

    static let history = Logger(subsystem: subsystem, category: "history")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let panel = Logger(subsystem: subsystem, category: "panel")
    static let snapshots = Logger(subsystem: subsystem, category: "snapshots")
}
