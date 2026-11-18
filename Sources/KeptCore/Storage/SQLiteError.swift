import CSQLite

/// An error reported by SQLite, with the connection's message for context.
public struct SQLiteError: Error, Equatable, CustomStringConvertible {
    /// The extended SQLite result code, such as `SQLITE_ERROR` (1) or
    /// `SQLITE_CONSTRAINT_UNIQUE` (2067).
    public let code: Int32
    /// SQLite's English description of what went wrong.
    public let message: String

    public init(code: Int32, message: String) {
        self.code = code
        self.message = message
    }

    /// Reads the most recent error message from `connection`, falling back to
    /// the generic text for `code` when there is no connection to ask.
    init(code: Int32, connection: OpaquePointer?) {
        let message = connection.map { String(cString: sqlite3_errmsg($0)) }
            ?? String(cString: sqlite3_errstr(code))
        self.init(code: code, message: message)
    }

    public var description: String {
        "SQLite error \(code): \(message)"
    }
}
