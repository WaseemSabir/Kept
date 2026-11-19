import Testing
@testable import KeptCore

@Suite("LRU cache")
struct LRUCacheTests {
    @Test("Evicts the least recently used beyond the count; reading refreshes, peeking doesn't")
    func countLimit() {
        var cache = LRUCache<String, Int>(countLimit: 3)
        cache.insert(1, for: "a")
        cache.insert(2, for: "b")
        cache.insert(3, for: "c")
        #expect(cache.value(for: "a") == 1)
        #expect(cache.peek("b") == 2)
        cache.insert(4, for: "d")
        #expect(cache.keys == ["d", "a", "c"])
        #expect(cache.peek("b") == nil)
        #expect(cache.count == 3)
    }

    @Test("Keeps the total cost under its limit and refuses a value that alone is over it")
    func costLimit() {
        var cache = LRUCache<String, String>(totalCostLimit: 100)
        cache.insert("row", for: "a", cost: 40)
        cache.insert("row", for: "b", cost: 40)
        #expect(cache.totalCost == 80)
        cache.insert("preview", for: "c", cost: 50)
        #expect(cache.keys == ["c", "b"])
        #expect(cache.totalCost == 90)

        cache.insert("huge", for: "d", cost: 101)
        #expect(cache.peek("d") == nil)
        #expect(cache.totalCost == 90)

        // Replacing a value replaces its cost.
        cache.insert("smaller", for: "c", cost: 10)
        #expect(cache.totalCost == 50)
        #expect(cache.keys == ["c", "b"])
    }

    @Test("Removes single values and everything, keeping the order consistent")
    func removal() {
        var cache = LRUCache<Int, Int>()
        for value in 0..<5 { cache.insert(value, for: value, cost: 1) }
        #expect(cache.removeValue(for: 2) == 2)
        #expect(cache.removeValue(for: 2) == nil)
        #expect(cache.removeValue(for: 4) == 4)  // the newest
        #expect(cache.removeValue(for: 0) == 0)  // the oldest
        #expect(cache.keys == [3, 1])
        _ = cache.value(for: 1)
        #expect(cache.keys == [1, 3])
        #expect(cache.totalCost == 2)
        cache.removeAll()
        #expect(cache.isEmpty)
        #expect(cache.totalCost == 0)
        cache.insert(9, for: 9)
        #expect(cache.keys == [9])
    }

    @Test("Survives a long random workout with its bounds intact")
    func randomWorkout() {
        var cache = LRUCache<Int, Int>(countLimit: 16, totalCostLimit: 1_000)
        var generator = SplitMix(seed: 42)
        for step in 0..<10_000 {
            let key = Int(generator.next() % 40)
            switch generator.next() % 3 {
            case 0: cache.insert(step, for: key, cost: Int(generator.next() % 200))
            case 1: _ = cache.value(for: key)
            default: cache.removeValue(for: key)
            }
            #expect(cache.count <= 16)
            #expect(cache.totalCost <= 1_000)
            #expect(cache.keys.count == cache.count)
        }
    }
}

/// A tiny deterministic random number generator for tests.
private struct SplitMix {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
