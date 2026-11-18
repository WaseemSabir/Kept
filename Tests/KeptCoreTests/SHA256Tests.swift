import Foundation
import Testing
@testable import KeptCore

@Suite("SHA-256")
struct SHA256Tests {
    @Test("Matches the FIPS 180-4 test vectors", arguments: [
        ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        (
            "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        ),
        (
            "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
            "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"
        ),
        ("The quick brown fox jumps over the lazy dog", "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"),
        ("Grüße, 世界 👋", "32128f4232c720cfb205d9ad3992fac5bd41596cd36c13b9a33323921a882f85"),
    ])
    func matchesVectors(input: String, digest: String) {
        #expect(SHA256.hexDigest(of: input) == digest)
        #expect(SHA256.hexDigest(of: Data(input.utf8)) == digest)
    }

    @Test("Pads correctly around block boundaries", arguments: [
        (55, "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318"),
        (56, "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"),
        (63, "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34"),
        (64, "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"),
        (65, "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0"),
        (119, "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb"),
        (120, "2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c"),
        (128, "6836cf13bac400e9105071cd6af47084dfacad4e5e302c94bfed24e013afb73e"),
    ])
    func padsAtBoundaries(length: Int, digest: String) {
        #expect(SHA256.hexDigest(of: String(repeating: "a", count: length)) == digest)
    }

    @Test("Hashes a million a's")
    func hashesAMillionAs() {
        let data = Data(repeating: UInt8(ascii: "a"), count: 1_000_000)
        #expect(SHA256.hexDigest(of: data) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    @Test("Gives the same digest however the input is split")
    func incrementalMatchesOneShot() {
        let data = Data((0..<1000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        let expected = SHA256.hexDigest(of: data)
        for chunkSize in [1, 3, 63, 64, 65, 200] {
            var hasher = SHA256()
            var offset = 0
            while offset < data.count {
                let end = min(offset + chunkSize, data.count)
                hasher.update(data.subdata(in: offset..<end))
                offset = end
            }
            #expect(hasher.finalizeHex() == expected, "chunk size \(chunkSize)")
        }
    }

    @Test("Hashes a slice of Data by its own bytes")
    func hashesDataSlices() {
        let whole = Data("xxabcxx".utf8)
        let slice = whole[whole.startIndex + 2..<whole.startIndex + 5]
        #expect(SHA256.hexDigest(of: slice) == SHA256.hexDigest(of: "abc"))
    }
}
