import CSQLite

/// A connection to an SQLite database.
///
/// A connection is not shared across isolation domains: the type that owns it
/// (the history store, on the main actor) is the only one that uses it.
public final class SQLiteDatabase {
    /// Where a database lives.
    public enum Location: Sendable, Equatable {
        /// A private database that exists only while the connection is open.
        case inMemory
        /// A database file at `path`, created if it doesn't exist yet.
        case file(path: String)

        var path: String {
            switch self {
            case .inMemory: ":memory:"
            case .file(let path): path
            }
        }
    }

    /// The version of the SQLite library Kept is linked against, e.g. "3.45.1".
    public static var libraryVersion: String {
        String(cString: sqlite3_libversion())
    }

    private let handle: OpaquePointer

    /// Opens (and if needed creates) the database at `location`.
    public init(_ location: Location) throws(SQLiteError) {
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(
            location.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
            nil
        )
        guard status == SQLITE_OK, let handle else {
            let error = SQLiteError(code: status, connection: handle)
            sqlite3_close_v2(handle)
            throw error
        }
        sqlite3_extended_result_codes(handle, 1)
        self.handle = handle
    }

    deinit {
        // `close_v2` defers the close until every statement is finalized.
        sqlite3_close_v2(handle)
    }

    /// Runs one or more SQL statements that don't return rows, such as
    /// schema changes.
    public func execute(_ sql: String) throws(SQLiteError) {
        let status = sqlite3_exec(handle, sql, nil, nil, nil)
        guard status == SQLITE_OK else {
            throw SQLiteError(code: status, connection: handle)
        }
    }

    /// Runs `sql` with `bindings` (numbered from 1) and steps it to completion.
    public func run(_ sql: String, _ bindings: SQLiteValue...) throws(SQLiteError) {
        let statement = try prepare(sql)
        try statement.bind(bindings)
        while try statement.step() {}
    }

    /// The first column of the first row `sql` returns, as an integer.
    public func scalarInt(_ sql: String) throws(SQLiteError) -> Int64? {
        let statement = try prepare(sql)
        guard try statement.step(), !statement.isNull(at: 0) else { return nil }
        return statement.int64(at: 0)
    }

    // MARK: Transactions

    /// Whether a transaction is open on this connection.
    public var isInTransaction: Bool {
        sqlite3_get_autocommit(handle) == 0
    }

    /// Starts a write transaction, taking the write lock right away.
    public func beginTransaction() throws(SQLiteError) {
        try execute("BEGIN IMMEDIATE")
    }

    public func commit() throws(SQLiteError) {
        try execute("COMMIT")
    }

    /// Rolls back the open transaction, if any. (SQLite may already have
    /// rolled back after some errors.)
    public func rollback() throws(SQLiteError) {
        guard isInTransaction else { return }
        try execute("ROLLBACK")
    }

    /// Runs `body` in a transaction: commits when it returns, rolls back when
    /// it throws.
    public func transaction<T>(_ body: () throws(SQLiteError) -> T) throws(SQLiteError) -> T {
        try beginTransaction()
        do throws(SQLiteError) {
            let result = try body()
            try commit()
            return result
        } catch {
            // The original error explains the failure better than a failed rollback would.
            try? rollback()
            throw error
        }
    }

    // MARK: Pragmas and status

    /// The schema version stored in the database header (`PRAGMA user_version`).
    public func userVersion() throws(SQLiteError) -> Int {
        Int(try scalarInt("PRAGMA user_version") ?? 0)
    }

    public func setUserVersion(_ version: Int) throws(SQLiteError) {
        try execute("PRAGMA user_version = \(version)")
    }

    /// Rows changed by the most recent INSERT, UPDATE or DELETE.
    public var changes: Int {
        Int(sqlite3_changes(handle))
    }

    /// Compiles a single SQL statement so it can be bound and stepped.
    public func prepare(_ sql: String) throws(SQLiteError) -> SQLiteStatement {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard status == SQLITE_OK else {
            throw SQLiteError(code: status, connection: handle)
        }
        guard let statement else {
            throw SQLiteError(code: SQLITE_MISUSE, message: "No SQL statement to prepare.")
        }
        return SQLiteStatement(handle: statement)
    }
}
