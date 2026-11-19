import Foundation

/// A value to bind to a statement parameter.
enum SQLiteValue: Sendable, Hashable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    static func int(_ value: Int) -> SQLiteValue { .integer(Int64(value)) }

    /// `.text`, or `.null` for `nil`.
    static func optional(_ value: String?) -> SQLiteValue { value.map(SQLiteValue.text) ?? .null }

    /// `.integer`, or `.null` for `nil`.
    static func optional(_ value: Int?) -> SQLiteValue { value.map { .integer(Int64($0)) } ?? .null }
}
