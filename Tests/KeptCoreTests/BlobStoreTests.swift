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
        let unrelated = store.directory.appendingPathComponent("README")
        try Data("not a blob".utf8).write(to: unrelated)

        #expect(try store.removeAll(except: [kept]) == 2)
        #expect(store.contains(kept))
        #expect(!store.contains(orphan))
        #expect(!FileManager.default.fileExists(atPath: leftover.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
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
