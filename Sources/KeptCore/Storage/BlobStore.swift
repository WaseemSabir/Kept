import Dispatch
import Foundation

/// Large payloads as content-addressed files: `<directory>/<sha256>`.
///
/// Files are written to a temporary name, flushed to disk and renamed into
/// place, readable only by the user (0600) in a private directory (0700).
/// Writing the same bytes twice stores them once; an existing file is reused
/// only after checking that it really holds those bytes.
///
/// Plain file I/O, safe from any thread. Capture writes blobs off the main
/// actor (`ClipStager`) before the clip is recorded, reserving them first;
/// `remove(_:)` and `removeAll(except:)` leave reserved blobs alone.
struct BlobStore: Sendable {
    let directory: URL
    /// Blobs written for clips that aren't recorded yet. Shared by every
    /// copy of this value.
    let reservations = BlobReservations()

    private static let temporaryPrefix = ".tmp-"
    /// Temporary files younger than this may belong to a write in progress
    /// (another Kept process, or this one), so a sweep leaves them alone.
    static let temporaryFileGracePeriod: TimeInterval = 10 * 60
    /// Existing files up to this size are compared byte for byte before
    /// reuse; larger ones by size and three samples.
    private static let fullVerificationLimit = 8 * 1024 * 1024
    private static let sampleLength = 64 * 1024

    init(directory: URL) throws(HistoryStoreError) {
        self.directory = directory
        try Self.createPrivateDirectory(at: directory)
    }

    /// Stores `data` and returns its hash (lowercase hex SHA-256).
    ///
    /// - Parameter knownHash: `data`'s hash when the caller already has it
    ///   (see `ClipRepresentation.sha256`), to skip hashing again.
    @discardableResult
    func write(_ data: Data, hash knownHash: String? = nil) throws(HistoryStoreError) -> String {
        let hash = knownHash ?? SHA256.hexDigest(of: data)
        guard Self.isValidHash(hash) else { throw .corruptRecord("Invalid blob hash \(hash)") }
        let destination = url(for: hash)
        if holds(data, at: destination) { return hash }

        let temporary = directory.appendingPathComponent(Self.temporaryPrefix + UUID().uuidString)
        try Self.writeDurably(data, to: temporary.path)
        // `rename` replaces a damaged file of the same name atomically.
        guard rename(temporary.path, destination.path) == 0 else {
            let reason = Self.describeErrno()
            unlink(temporary.path)
            throw .fileSystem(path: destination.path, reason: reason)
        }
        Self.synchronizeDirectory(at: directory.path)
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

    /// Deletes the blob unless it's reserved for a clip being recorded.
    func remove(_ hash: String) throws(HistoryStoreError) {
        guard Self.isValidHash(hash) else { return }
        let location = url(for: hash)
        try reservations.unlessReserved(hash) { () throws(HistoryStoreError) in
            do {
                try Self.removeFile(at: location)
            } catch {
                throw .fileSystem(path: location.path, reason: error.localizedDescription)
            }
        }
    }

    /// Deletes these blobs on a background queue, so a big batch (old
    /// clips forgotten at once) doesn't hold up the main actor. The caller
    /// has checked that no clip references them; a hash reserved before
    /// its turn comes (a capture or an edit using the same bytes again)
    /// keeps its file. Failures are left for the next launch's sweep.
    func removeInBackground(_ hashes: Set<String>) {
        let hashes = hashes.filter(Self.isValidHash)
        guard !hashes.isEmpty else { return }
        reservations.markForRemoval(hashes)
        let store = self
        Self.removalQueue.async {
            for hash in hashes {
                let location = store.url(for: hash)
                store.reservations.removeIfStillPending(hash) {
                    _ = try? Self.removeFile(at: location)
                }
            }
        }
    }

    /// Returns once every `removeInBackground(_:)` so far has finished.
    func waitForBackgroundRemovals() {
        Self.removalQueue.sync {}
    }

    /// Where `removeInBackground(_:)` deletes files, one batch at a time.
    private static let removalQueue = DispatchQueue(label: "app.kept.blob-removal", qos: .utility)

    /// The hashes of every stored blob.
    func storedHashes() throws(HistoryStoreError) -> Set<String> {
        Set(try fileNames().filter(Self.isValidHash))
    }

    /// Deletes every blob not in `referenced` (and not reserved), plus
    /// temporary files left by interrupted writes that are older than
    /// `gracePeriod`. Tries every file before reporting the first failure.
    /// Returns how many files were removed.
    @discardableResult
    func removeAll(
        except referenced: Set<String>,
        keepingTemporaryFilesNewerThan gracePeriod: TimeInterval = BlobStore.temporaryFileGracePeriod,
        now: Date = Date()
    ) throws(HistoryStoreError) -> Int {
        try removeAll(named: fileNames(), except: referenced, keepingTemporaryFilesNewerThan: gracePeriod, now: now)
    }

    /// `removeAll(except:keepingTemporaryFilesNewerThan:now:)` over `names`,
    /// the folder's listing. A write running meanwhile may rename or delete
    /// a listed file: a temporary file whose date can't be read is left
    /// alone, and a file that's already gone isn't a failure.
    func removeAll(
        named names: [String],
        except referenced: Set<String>,
        keepingTemporaryFilesNewerThan gracePeriod: TimeInterval,
        now: Date
    ) throws(HistoryStoreError) -> Int {
        var removed = 0
        var firstFailure: HistoryStoreError?
        for name in names {
            let location = directory.appendingPathComponent(name)
            if name.hasPrefix(Self.temporaryPrefix) {
                let attributes = try? FileManager.default.attributesOfItem(atPath: location.path)
                guard let modified = attributes?[.modificationDate] as? Date,
                      now.timeIntervalSince(modified) >= gracePeriod
                else { continue }
            } else if !Self.isValidHash(name) || referenced.contains(name) {
                continue
            }
            do {
                // Temporary names are never reserved, so they go unconditionally.
                var didRemove = false
                try reservations.unlessReserved(name) {
                    didRemove = try Self.removeFile(at: location)
                }
                if didRemove { removed += 1 }
            } catch {
                firstFailure = firstFailure ?? .fileSystem(path: location.path, reason: error.localizedDescription)
            }
        }
        if let firstFailure { throw firstFailure }
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

    // MARK: Verifying and writing files

    /// Whether the file at `url` holds exactly `data`: same size, and the
    /// same bytes (all of them, or the start, middle and end of a large file).
    private func holds(_ data: Data, at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              (attributes[.size] as? NSNumber)?.intValue == data.count
        else { return false }

        if data.count <= Self.fullVerificationLimit {
            return (try? Data(contentsOf: url)) == data
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let length = Self.sampleLength
        for offset in [0, data.count / 2 - length / 2, data.count - length] {
            guard (try? handle.seek(toOffset: UInt64(offset))) != nil,
                  let sample = try? handle.read(upToCount: length),
                  sample == data.subdata(in: offset..<offset + length)
            else { return false }
        }
        return true
    }

    /// Creates `path` (0600, failing if it exists), writes `data` and flushes
    /// it to disk before returning, so a rename after it can't publish a
    /// partly written file after a crash.
    private static func writeDurably(_ data: Data, to path: String) throws(HistoryStoreError) {
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else {
            throw .fileSystem(path: path, reason: describeErrno())
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            unlink(path)
            throw .fileSystem(path: path, reason: error.localizedDescription)
        }
    }

    /// Deletes the file at `url`. Returns `false` when it was already gone
    /// (renamed or deleted by a write or deletion running meanwhile), which
    /// isn't a failure.
    @discardableResult
    private static func removeFile(at url: URL) throws -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            var status = stat()
            if lstat(url.path, &status) != 0, errno == ENOENT { return false }
            throw error
        }
    }

    /// Flushes a directory entry change (a rename) to disk. Best effort.
    static func synchronizeDirectory(at path: String) {
        let descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else { return }
        _ = fsync(descriptor)
        _ = close(descriptor)
    }

    private static func describeErrno() -> String {
        String(cString: strerror(errno))
    }

    /// 64 lowercase hex digits; anything else is never used as a file name.
    static func isValidHash(_ hash: String) -> Bool {
        hash.utf8.count == 64 && hash.utf8.allSatisfy { byte in
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
        }
    }

    /// Creates the folder (0700), or makes an existing one private.
    static func createPrivateDirectory(at url: URL) throws(HistoryStoreError) {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw .fileSystem(path: url.path, reason: "A file is in the way of the folder.")
            }
            makePrivate(url.path, permissions: 0o700)
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

    /// Restricts an existing file or folder to `permissions` when it's
    /// looser. Best effort: a file Kept can't change is still usable.
    static func makePrivate(_ path: String, permissions: Int) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let current = (attributes[.posixPermissions] as? NSNumber)?.intValue,
              current & 0o777 != permissions
        else { return }
        try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
    }
}
