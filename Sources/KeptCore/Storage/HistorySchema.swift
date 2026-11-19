/// The history database schema and its migrations.
///
/// `PRAGMA user_version` records how many migrations have run. Append new
/// migrations; never edit a shipped one.
enum HistorySchema {
    static let migrations: [String] = [
        // 1: clips and their pasteboard representations.
        """
        CREATE TABLE clips (
            id TEXT PRIMARY KEY NOT NULL,
            kind TEXT NOT NULL,
            title TEXT NOT NULL,
            search_text TEXT NOT NULL,
            content_hash TEXT NOT NULL UNIQUE,
            source_bundle_id TEXT,
            first_copied_at REAL NOT NULL,
            last_copied_at REAL NOT NULL,
            copy_count INTEGER NOT NULL DEFAULT 1,
            pin_order INTEGER,
            byte_size INTEGER NOT NULL,
            metadata TEXT NOT NULL DEFAULT '{}'
        );
        CREATE INDEX clips_by_last_copied ON clips (last_copied_at DESC);
        CREATE INDEX clips_by_pin_order ON clips (pin_order) WHERE pin_order IS NOT NULL;

        CREATE TABLE representations (
            clip_id TEXT NOT NULL REFERENCES clips (id) ON DELETE CASCADE,
            item_index INTEGER NOT NULL,
            position INTEGER NOT NULL,
            type TEXT NOT NULL,
            data BLOB,
            blob_hash TEXT,
            size INTEGER NOT NULL,
            PRIMARY KEY (clip_id, item_index, position),
            CHECK ((data IS NULL) <> (blob_hash IS NULL))
        );
        CREATE INDEX representations_by_blob ON representations (blob_hash) WHERE blob_hash IS NOT NULL;
        """,
        // 2: a name the user gives a clip; NULL shows the generated title.
        """
        ALTER TABLE clips ADD COLUMN custom_title TEXT;
        """,
    ]

    static var currentVersion: Int { migrations.count }

    /// Brings `database` up to `currentVersion`, one transaction per migration.
    static func migrate(_ database: SQLiteDatabase) throws(HistoryStoreError) {
        let version: Int
        do throws(SQLiteError) { version = try database.userVersion() } catch { throw .database(error) }
        guard version <= currentVersion else { throw .newerSchema(version: version) }

        do throws(SQLiteError) {
            for next in version..<currentVersion {
                try database.transaction { () throws(SQLiteError) in
                    try database.execute(migrations[next])
                    try database.setUserVersion(next + 1)
                }
            }
        } catch {
            throw .database(error)
        }
    }
}
