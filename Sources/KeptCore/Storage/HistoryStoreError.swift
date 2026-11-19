import Foundation

/// Why a history operation failed.
public enum HistoryStoreError: Error, Equatable, CustomStringConvertible {
    /// SQLite reported an error.
    case database(SQLiteError)
    /// Reading or writing a file failed.
    case fileSystem(path: String, reason: String)
    /// A representation points at a blob file that is gone.
    case missingBlob(hash: String)
    /// No clip has this ID.
    case clipNotFound(UUID)
    /// The database was written by a newer Kept with a schema this one doesn't know.
    case newerSchema(version: Int)
    /// A stored row couldn't be read back.
    case corruptRecord(String)
    /// The clip isn't text (an image or files), so it can't be edited as text.
    case notEditable(UUID)
    /// The edited text has nothing visible in it.
    case emptyText

    public var description: String {
        switch self {
        case .database(let error): "History database error: \(error)"
        case .fileSystem(let path, let reason): "Couldn't access \(path): \(reason)"
        case .missingBlob(let hash): "Missing stored data \(hash)"
        case .clipNotFound(let id): "No clip with ID \(id)"
        case .newerSchema(let version): "History was saved by a newer Kept (schema \(version))"
        case .corruptRecord(let detail): "Unreadable history record: \(detail)"
        case .notEditable(let id): "Clip \(id) isn't text, so it can't be edited"
        case .emptyText: "The edited text is empty"
        }
    }
}
