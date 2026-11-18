import CSQLite

/// A compiled SQL statement.
///
/// Parameters are numbered from 1 and result columns from 0, as in SQLite.
public final class SQLiteStatement {
    private let handle: OpaquePointer

    init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_finalize(handle)
    }

    // MARK: Binding

    public func bind(_ value: Int64, at index: Int) throws(SQLiteError) {
        try check(sqlite3_bind_int64(handle, Int32(index), value))
    }

    public func bind(_ value: String, at index: Int) throws(SQLiteError) {
        let status = sqlite3_bind_text64(
            handle,
            Int32(index),
            value,
            sqlite3_uint64(value.utf8.count),
            csqlite_transient(),
            UInt8(SQLITE_UTF8)
        )
        try check(status)
    }

    public func bindNull(at index: Int) throws(SQLiteError) {
        try check(sqlite3_bind_null(handle, Int32(index)))
    }

    // MARK: Stepping

    /// Advances to the next result row.
    ///
    /// - Returns: `true` while a row is available to read, `false` once the
    ///   statement has finished.
    @discardableResult
    public func step() throws(SQLiteError) -> Bool {
        switch sqlite3_step(handle) {
        case SQLITE_ROW: true
        case SQLITE_DONE: false
        case let status: throw error(for: status)
        }
    }

    /// Rewinds the statement so it can run again, keeping its bindings.
    public func reset() throws(SQLiteError) {
        try check(sqlite3_reset(handle))
    }

    // MARK: Reading columns

    public func int64(at column: Int) -> Int64 {
        sqlite3_column_int64(handle, Int32(column))
    }

    /// The column's text, or `nil` when it is `NULL`.
    public func string(at column: Int) -> String? {
        guard let text = sqlite3_column_text(handle, Int32(column)) else { return nil }
        let count = Int(sqlite3_column_bytes(handle, Int32(column)))
        return String(decoding: UnsafeBufferPointer(start: text, count: count), as: UTF8.self)
    }

    // MARK: Errors

    private func check(_ status: Int32) throws(SQLiteError) {
        guard status == SQLITE_OK else { throw error(for: status) }
    }

    private func error(for status: Int32) -> SQLiteError {
        SQLiteError(code: status, connection: sqlite3_db_handle(handle))
    }
}
