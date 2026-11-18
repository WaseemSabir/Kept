import Foundation
import Testing
@testable import KeptCore

@Suite("SQLite")
struct SQLiteDatabaseTests {
    @Test("Links SQLite 3")
    func linksSQLite3() {
        #expect(SQLiteDatabase.libraryVersion.hasPrefix("3."))
    }

    @Test("Opens an in-memory database and runs a query")
    func runsAQueryInMemory() throws {
        let database = try SQLiteDatabase(.inMemory)
        let statement = try database.prepare("SELECT 1 + 1")

        #expect(try statement.step())
        #expect(statement.int64(at: 0) == 2)
        #expect(try statement.step() == false)
    }

    @Test("Round-trips bound integers, text and NULL")
    func roundTripsBoundValues() throws {
        let database = try SQLiteDatabase(.inMemory)
        try database.execute("CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT, note TEXT)")

        let insert = try database.prepare("INSERT INTO notes (id, body, note) VALUES (?, ?, ?)")
        try insert.bind(7, at: 1)
        try insert.bind("Grüße, 世界 👋", at: 2)
        try insert.bindNull(at: 3)
        #expect(try insert.step() == false)

        let select = try database.prepare("SELECT id, body, note FROM notes")
        #expect(try select.step())
        #expect(select.int64(at: 0) == 7)
        #expect(select.string(at: 1) == "Grüße, 世界 👋")
        #expect(select.string(at: 2) == nil)
        #expect(try select.step() == false)
    }

    @Test("Runs a statement again after reset")
    func reusesAStatementAfterReset() throws {
        let database = try SQLiteDatabase(.inMemory)
        let statement = try database.prepare("SELECT ?")
        try statement.bind("first", at: 1)
        #expect(try statement.step())
        #expect(statement.string(at: 0) == "first")

        try statement.reset()
        try statement.bind("second", at: 1)
        #expect(try statement.step())
        #expect(statement.string(at: 0) == "second")
    }

    @Test("Keeps data in a database file across connections")
    func persistsToAFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeptCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let location = SQLiteDatabase.Location.file(path: directory.appendingPathComponent("kept.sqlite").path)

        do {
            let database = try SQLiteDatabase(location)
            try database.execute("CREATE TABLE kept (value TEXT); INSERT INTO kept VALUES ('hello');")
        }

        let reopened = try SQLiteDatabase(location)
        let select = try reopened.prepare("SELECT value FROM kept")
        #expect(try select.step())
        #expect(select.string(at: 0) == "hello")
    }

    @Test("Reports SQLite's error message")
    func reportsErrors() throws {
        let database = try SQLiteDatabase(.inMemory)

        let error = #expect(throws: SQLiteError.self) {
            try database.execute("SELEKT 1")
        }
        #expect(error?.code == 1)  // SQLITE_ERROR
        #expect(error?.message.contains("syntax error") == true)
    }

    @Test("Rejects SQL with no statement in it")
    func rejectsEmptySQL() throws {
        let database = try SQLiteDatabase(.inMemory)

        #expect(throws: SQLiteError.self) {
            try database.prepare("  -- nothing here")
        }
    }
}
