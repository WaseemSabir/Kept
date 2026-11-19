/// A bounded cache that drops the least recently used values first.
///
/// Bounded by a count and by a total cost (bytes, say): inserting past
/// either limit evicts from the least recently used end until both hold. A
/// value costing more than `totalCostLimit` on its own isn't kept. Reading
/// a value with `value(for:)` marks it as recently used; `peek(_:)` doesn't.
/// Every operation is O(1).
public struct LRUCache<Key: Hashable, Value> {
    fileprivate struct Entry {
        var value: Value
        var cost: Int
        /// The entry used just before this one, towards the least recent end.
        var older: Key?
        /// The entry used just after this one, towards the most recent end.
        var newer: Key?
    }

    public let countLimit: Int
    public let totalCostLimit: Int
    /// The sum of the costs of the values held.
    public private(set) var totalCost = 0

    private var entries: [Key: Entry] = [:]
    private var newest: Key?
    private var oldest: Key?

    public init(countLimit: Int = .max, totalCostLimit: Int = .max) {
        self.countLimit = max(0, countLimit)
        self.totalCostLimit = max(0, totalCostLimit)
    }

    public var count: Int { entries.count }

    public var isEmpty: Bool { entries.isEmpty }

    /// The keys from the most to the least recently used.
    public var keys: [Key] {
        var keys: [Key] = []
        keys.reserveCapacity(entries.count)
        var cursor = newest
        while let key = cursor, let entry = entries[key] {
            keys.append(key)
            cursor = entry.older
        }
        return keys
    }

    /// The value for `key`, marking it as the most recently used.
    public mutating func value(for key: Key) -> Value? {
        guard let entry = entries[key] else { return nil }
        moveToNewest(key)
        return entry.value
    }

    /// The value for `key`, leaving the order alone.
    public func peek(_ key: Key) -> Value? {
        entries[key]?.value
    }

    /// Stores `value` as the most recently used, replacing any value for
    /// `key`, then evicts what no longer fits.
    public mutating func insert(_ value: Value, for key: Key, cost: Int = 0) {
        let cost = max(0, cost)
        removeValue(for: key)
        guard cost <= totalCostLimit, countLimit > 0 else { return }
        entries[key] = Entry(value: value, cost: cost, older: newest, newer: nil)
        if let newest { entries[newest]?.newer = key }
        newest = key
        if oldest == nil { oldest = key }
        totalCost += cost
        while entries.count > countLimit || totalCost > totalCostLimit, let oldest {
            removeValue(for: oldest)
        }
    }

    /// Removes and returns the value for `key`.
    @discardableResult
    public mutating func removeValue(for key: Key) -> Value? {
        guard let entry = entries.removeValue(forKey: key) else { return nil }
        if let older = entry.older { entries[older]?.newer = entry.newer } else { oldest = entry.newer }
        if let newer = entry.newer { entries[newer]?.older = entry.older } else { newest = entry.older }
        totalCost -= entry.cost
        return entry.value
    }

    public mutating func removeAll() {
        entries.removeAll()
        newest = nil
        oldest = nil
        totalCost = 0
    }

    private mutating func moveToNewest(_ key: Key) {
        guard newest != key, let entry = entries[key] else { return }
        // Unlink…
        if let older = entry.older { entries[older]?.newer = entry.newer } else { oldest = entry.newer }
        if let newer = entry.newer { entries[newer]?.older = entry.older }
        // …and relink at the newest end.
        entries[key]?.older = newest
        entries[key]?.newer = nil
        if let newest { entries[newest]?.newer = key }
        newest = key
    }
}

extension LRUCache: Sendable where Key: Sendable, Value: Sendable {}

extension LRUCache.Entry: Sendable where Key: Sendable, Value: Sendable {}
