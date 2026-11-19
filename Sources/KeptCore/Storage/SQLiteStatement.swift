import CSQLite
import Foundation

/// A compiled SQL statement.
///
/// Parameters are numbered from 1 and result columns from 0, as in SQLite.
final class SQLiteStatement {
    private let handle: OpaquePointer

    init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_finalize(handle)
    }

    // MARK: Binding

    func bind(_ value: Int64, at index: Int) throws(SQLiteError) {
        try check(sqlite3_bind_int64(handle, Int32(index), value))
    }

    func bind(_ value: String, at index: Int) throws(SQLiteError) {
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

    func bind(_ value: Int, at index: Int) throws(SQLiteError) {
        try bind(Int64(value), at: index)
    }

    func bind(_ value: Double, at index: Int) throws(SQLiteError) {
        try check(sqlite3_bind_double(handle, Int32(index), value))
    }

    /// Binds `value` as a blob; empty data binds an empty blob, not `NULL`.
    func bind(_ value: Data, at index: Int) throws(SQLiteError) {
        let status = value.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress, !bytes.isEmpty else {
                return sqlite3_bind_zeroblob(handle, Int32(index), 0)
            }
            return sqlite3_bind_blob64(handle, Int32(index), base, sqlite3_uint64(bytes.count), csqlite_transient())
        }
        try check(status)
    }

    func bindNull(at index: Int) throws(SQLiteError) {
        try check(sqlite3_bind_null(handle, Int32(index)))
    }

    func bind(_ value: SQLiteValue, at index: Int) throws(SQLiteError) {
        switch value {
        case .null: try bindNull(at: index)
        case .integer(let value): try bind(value, at: index)
        case .real(let value): try bind(value, at: index)
        case .text(let value): try bind(value, at: index)
        case .blob(let value): try bind(value, at: index)
        }
    }

    /// Binds `values` to parameters 1, 2, 3…
    func bind(_ values: [SQLiteValue]) throws(SQLiteError) {
        for (offset, value) in values.enumerated() {
            try bind(value, at: offset + 1)
        }
    }

    // MARK: Stepping

    /// Advances to the next result row.
    ///
    /// - Returns: `true` while a row is available to read, `false` once the
    ///   statement has finished.
    @discardableResult
    func step() throws(SQLiteError) -> Bool {
        switch sqlite3_step(handle) {
        case SQLITE_ROW: true
        case SQLITE_DONE: false
        case let status: throw error(for: status)
        }
    }

    /// Rewinds the statement so it can run again, keeping its bindings.
    func reset() throws(SQLiteError) {
        try check(sqlite3_reset(handle))
    }

    /// Steps the statement to completion, ignoring any rows.
    func run() throws(SQLiteError) {
        while try step() {}
    }

    // MARK: Reading columns

    func isNull(at column: Int) -> Bool {
        sqlite3_column_type(handle, Int32(column)) == SQLITE_NULL
    }

    func int64(at column: Int) -> Int64 {
        sqlite3_column_int64(handle, Int32(column))
    }

    func int(at column: Int) -> Int {
        Int(int64(at: column))
    }

    func double(at column: Int) -> Double {
        sqlite3_column_double(handle, Int32(column))
    }

    /// The column's bytes, or `nil` when it is `NULL`.
    func data(at column: Int) -> Data? {
        guard !isNull(at: column) else { return nil }
        // Ask for the pointer before the length, as SQLite recommends.
        let bytes = sqlite3_column_blob(handle, Int32(column))
        let count = Int(sqlite3_column_bytes(handle, Int32(column)))
        guard let bytes, count > 0 else { return Data() }
        return Data(bytes: bytes, count: count)
    }

    /// The column's text, or `nil` when it is `NULL`.
    func string(at column: Int) -> String? {
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
