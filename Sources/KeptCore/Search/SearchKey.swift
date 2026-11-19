import Foundation

/// Text folded for matching: lowercased, with diacritics and compatibility
/// forms removed ("Café" → "cafe", "ﬁ" → "fi", "Straße" → "strasse"), as
/// UTF-8 bytes so matching can scan memory directly.
///
/// Folding runs for every clip at launch, so it avoids Foundation and
/// per-scalar allocations: ASCII is folded in place, and every other scalar
/// is looked up in a table of 256 folded scalars, built once per Unicode
/// block on first use. Each table entry is the compatibility decomposition
/// of one scalar, without nonspacing and enclosing marks, lowercased.
struct SearchKey: Sendable, Hashable {
    let bytes: [UInt8]

    init(_ text: String) {
        bytes = SearchKey.fold(text)
    }

    static func fold(_ text: String) -> [UInt8] {
        var bytes = Array(text.utf8)
        if bytes.allSatisfy({ $0 < 0x80 }) {
            for index in bytes.indices where (0x41...0x5A).contains(bytes[index]) {
                bytes[index] |= 0x20
            }
            return bytes
        }

        var folded: [UInt8] = []
        folded.reserveCapacity(bytes.count)
        var cache = BlockCache()
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if value < 0x80 {
                let byte = UInt8(value)
                folded.append((0x41...0x5A).contains(byte) ? byte | 0x20 : byte)
            } else {
                cache.block(containing: value).appendFolded(value, to: &folded)
            }
        }
        return folded
    }

    // MARK: Tables

    /// The folded form of 256 consecutive scalars, read-only once built.
    final class Block: Sendable {
        private let bytes: [UInt8]
        /// `ends[i]` is where scalar `i`'s folded bytes end; they start at `ends[i - 1]` (or 0).
        private let ends: [Int]

        init(index: UInt32) {
            var bytes: [UInt8] = []
            var ends: [Int] = []
            ends.reserveCapacity(256)
            for low in UInt32(0)..<256 {
                if let scalar = Unicode.Scalar(index << 8 | low) {
                    bytes += SearchKey.foldSlowly(scalar)
                }
                ends.append(bytes.count)
            }
            self.bytes = bytes
            self.ends = ends
        }

        func appendFolded(_ value: UInt32, to output: inout [UInt8]) {
            let low = Int(value & 0xFF)
            let start = low == 0 ? 0 : ends[low - 1]
            output.append(contentsOf: bytes[start..<ends[low]])
        }
    }

    /// Every block built so far, shared by all threads.
    private final class Blocks: @unchecked Sendable {
        private let lock = NSLock()
        private var blocks: [UInt32: Block] = [:]

        func block(_ index: UInt32) -> Block {
            lock.lock()
            defer { lock.unlock() }
            if let block = blocks[index] { return block }
            let block = Block(index: index)
            blocks[index] = block
            return block
        }
    }

    private static let blocks = Blocks()

    /// The last two blocks one fold used, so most scalars skip the lock.
    private struct BlockCache {
        private var first: (index: UInt32, block: Block)?
        private var second: (index: UInt32, block: Block)?

        mutating func block(containing value: UInt32) -> Block {
            let index = value >> 8
            if let first, first.index == index { return first.block }
            if let second, second.index == index {
                self.second = first
                first = second
                return second.block
            }
            let block = SearchKey.blocks.block(index)
            second = first
            first = (index, block)
            return block
        }
    }

    /// One scalar folded the slow way, with Foundation's decomposition.
    static func foldSlowly(_ scalar: Unicode.Scalar) -> [UInt8] {
        var folded: [UInt8] = []
        for part in String(Character(scalar)).decomposedStringWithCompatibilityMapping.unicodeScalars {
            if part.isASCII {
                let value = UInt8(part.value)
                folded.append((0x41...0x5A).contains(value) ? value | 0x20 : value)
                continue
            }
            switch part.properties.generalCategory {
            case .nonspacingMark, .enclosingMark: continue
            default: break
            }
            for lowered in part.properties.lowercaseMapping.unicodeScalars {
                if let replacement = foldedLetters[lowered.value] {
                    folded.append(contentsOf: replacement.utf8)
                } else {
                    UTF8.encode(lowered) { folded.append($0) }
                }
            }
        }
        return folded
    }

    /// Letters with no decomposition that people type without the mark.
    private static let foldedLetters: [UInt32: String] = [
        0x00DF: "ss", 0x00E6: "ae", 0x0153: "oe", 0x00F8: "o", 0x0111: "d", 0x00F0: "d",
        0x0142: "l", 0x0127: "h", 0x0131: "i", 0x00FE: "th",
    ]
}
