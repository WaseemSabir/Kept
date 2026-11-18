import Foundation

/// Large payloads as content-addressed files: `<directory>/<sha256>`.
///
/// Files are written to a temporary name and renamed into place, readable
/// only by the user (0600) in a private directory (0700). Writing the same
/// bytes twice stores them once.
struct BlobStore: Sendable {
    let directory: URL

    private static let temporaryPrefix = ".tmp-"

    init(directory: URL) throws(HistoryStoreError) {
        self.directory = directory
        try Self.createPrivateDirectory(at: directory)
    }

    /// Stores `data` and returns its hash (lowercase hex SHA-256).
    @discardableResult
    func write(_ data: Data) throws(HistoryStoreError) -> String {
        let hash = SHA256.hexDigest(of: data)
        let destination = url(for: hash)
        if FileManager.default.fileExists(atPath: destination.path) { return hash }

        let temporary = directory.appendingPathComponent(Self.temporaryPrefix + UUID().uuidString)
        let created = FileManager.default.createFile(
            atPath: temporary.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        )
        guard created else {
            throw .fileSystem(path: temporary.path, reason: "The file couldn't be created.")
        }
        do {
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw .fileSystem(path: destination.path, reason: error.localizedDescription)
        }
        return hash
    }

    func read(_ hash: String) throws(HistoryStoreError) -> Data {
        guard Self.isValidHash(hash) else { throw .corruptRecord("Invalid blob hash \(hash)") }
        let location = url(for: hash)
        guard FileManager.default.fileExists(atPath: location.path) else { throw .missingBlob(hash: hash) }
        do {
            return try Data(contentsOf: location)
        } catch {
            throw .fileSystem(path: location.path, reason: error.localizedDescription)
        }
    }

    func contains(_ hash: String) -> Bool {
        Self.isValidHash(hash) && FileManager.default.fileExists(atPath: url(for: hash).path)
    }

    func remove(_ hash: String) throws(HistoryStoreError) {
        guard Self.isValidHash(hash) else { return }
        let location = url(for: hash)
        guard FileManager.default.fileExists(atPath: location.path) else { return }
        do {
            try FileManager.default.removeItem(at: location)
        } catch {
            throw .fileSystem(path: location.path, reason: error.localizedDescription)
        }
    }

    /// The hashes of every stored blob.
    func storedHashes() throws(HistoryStoreError) -> Set<String> {
        Set(try fileNames().filter(Self.isValidHash))
    }

    /// Deletes every blob not in `referenced`, plus temporary files left by
    /// interrupted writes. Returns how many files were removed.
    @discardableResult
    func removeAll(except referenced: Set<String>) throws(HistoryStoreError) -> Int {
        var removed = 0
        for name in try fileNames() {
            let isOrphan = Self.isValidHash(name) && !referenced.contains(name)
            guard isOrphan || name.hasPrefix(Self.temporaryPrefix) else { continue }
            let location = directory.appendingPathComponent(name)
            do {
                try FileManager.default.removeItem(at: location)
                removed += 1
            } catch {
                throw .fileSystem(path: location.path, reason: error.localizedDescription)
            }
        }
        return removed
    }

    func url(for hash: String) -> URL {
        directory.appendingPathComponent(hash)
    }

    private func fileNames() throws(HistoryStoreError) -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch {
            throw .fileSystem(path: directory.path, reason: error.localizedDescription)
        }
    }

    /// 64 lowercase hex digits; anything else is never used as a file name.
    static func isValidHash(_ hash: String) -> Bool {
        hash.utf8.count == 64 && hash.utf8.allSatisfy { byte in
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
        }
    }

    static func createPrivateDirectory(at url: URL) throws(HistoryStoreError) {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw .fileSystem(path: url.path, reason: "A file is in the way of the folder.")
            }
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw .fileSystem(path: url.path, reason: error.localizedDescription)
        }
    }
}
