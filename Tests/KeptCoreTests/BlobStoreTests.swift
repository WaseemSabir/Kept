import Foundation
import Testing
@testable import KeptCore

@Suite("Blob store")
struct BlobStoreTests {
    @Test("Writes data under its hash and reads it back")
    func writesAndReads() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let store = try BlobStore(directory: directory.appendingPathComponent("blobs"))

        let data = Data((0..<100_000).map { UInt8(truncatingIfNeeded: $0) })
        let hash = try store.write(data)
        #expect(hash == SHA256.hexDigest(of: data))
        #expect(try store.read(hash) == data)
        #expect(store.contains(hash))
        #expect(try store.storedHashes() == [hash])
        #expect(try store.write(data) == hash)  // stored once
        #expect(try store.storedHashes().count == 1)
    }

    @Test("Keeps files private to the user")
    func usesPrivatePermissions() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let store = try BlobStore(directory: directory.appendingPathComponent("blobs"))
        let hash = try store.write(Data("secret".utf8))

        let fileAttributes = try FileManager.default.attributesOfItem(atPath: store.url(for: hash).path)
        #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let folderAttributes = try FileManager.default.attributesOfItem(atPath: store.directory.path)
        #expect((folderAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test("Removes orphans and leftover temporary files")
    func removesOrphans() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let store = try BlobStore(directory: directory.appendingPathComponent("blobs"))
        let kept = try store.write(Data("kept".utf8))
        let orphan = try store.write(Data("orphan".utf8))
        let leftover = store.directory.appendingPathComponent(".tmp-interrupted")
        try Data("partial".utf8).write(to: leftover)
        try age(leftover, by: BlobStore.temporaryFileGracePeriod + 60)
        let inProgress = store.directory.appendingPathComponent(".tmp-writing")
        try Data("partial".utf8).write(to: inProgress)
        let unrelated = store.directory.appendingPathComponent("README")
        try Data("not a blob".utf8).write(to: unrelated)

        #expect(try store.removeAll(except: [kept]) == 2)
        #expect(store.contains(kept))
        #expect(!store.contains(orphan))
        #expect(!FileManager.default.fileExists(atPath: leftover.path))
        #expect(FileManager.default.fileExists(atPath: inProgress.path), "a recent temporary file may be a write in progress")
        #expect(FileManager.default.fileExists(atPath: unrelated.path))

        #expect(try store.removeAll(except: [kept], now: Date().addingTimeInterval(BlobStore.temporaryFileGracePeriod + 60)) == 1)
        #expect(!FileManager.default.fileExists(atPath: inProgress.path))
    }

    @Test("Rewrites a damaged file instead of trusting its name")
    func verifiesBeforeReuse() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let store = try BlobStore(directory: directory.appendingPathComponent("blobs"))
        let data = Data((0..<10_000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        let hash = try store.write(data)
        let location = store.url(for: hash)

        // Same size, different bytes (e.g. zeroed pages after a crash).
        try Data(repeating: 0, count: data.count).write(to: location)
        #expect(try store.write(data) == hash)
        #expect(try store.read(hash) == data)

        // Truncated.
        try data.prefix(100).write(to: location)
        #expect(try store.write(data) == hash)
        #expect(try store.read(hash) == data)
        let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path) == [hash])
    }

    @Test("Checks large files by size and samples before reuse")
    func verifiesLargeFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let store = try BlobStore(directory: directory.appendingPathComponent("blobs"))
        let data = Data(repeating: 0x5A, count: 9 * 1024 * 1024)
        // A known hash is trusted (hashing 9 MB is slow in debug builds).
        let hash = String(repeating: "c", count: 64)
        #expect(try store.write(data, hash: hash) == hash)

        var damaged = data
        damaged[damaged.count - 1] = 0
        try damaged.write(to: store.url(for: hash))
        try store.write(data, hash: hash)
        #expect(try store.read(hash) == data)
    }

    @Test("Makes an existing folder private")
    func tightensExistingFolder() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let folder = directory.appendingPathComponent("blobs")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        _ = try BlobStore(directory: folder)
        let attributes = try FileManager.default.attributesOfItem(atPath: folder.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    private func age(_ url: URL, by seconds: TimeInterval) throws {
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-seconds)], ofItemAtPath: url.path)
    }

    @Test("Reports missing blobs and refuses invalid hashes")
    func rejectsBadHashes() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let store = try BlobStore(directory: directory.appendingPathComponent("blobs"))
        let missing = String(repeating: "a", count: 64)

        #expect(throws: HistoryStoreError.missingBlob(hash: missing)) { try store.read(missing) }
        #expect(throws: HistoryStoreError.self) { try store.read("../../etc/passwd") }
        #expect(!store.contains("../History.sqlite"))
        try store.remove(missing)  // nothing to remove is fine
    }
}
