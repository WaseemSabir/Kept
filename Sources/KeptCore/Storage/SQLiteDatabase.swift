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
