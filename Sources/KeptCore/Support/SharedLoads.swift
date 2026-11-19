/// Runs slow loads (disk reads, decoding) off the main actor, one per key
/// at a time, for callers on the main actor.
///
/// Callers asking for a key that's already loading wait for the same
/// result instead of starting another load. A caller that's cancelled gets
/// `nil` straight away, without waiting for the load; once every caller
/// waiting on a load has been cancelled, the load itself is cancelled (it
/// should check `Task.isCancelled`) and forgotten, so the next request
/// starts afresh. Caching results is up to the caller.
@MainActor
public final class SharedLoads<Key: Hashable & Sendable, Value: Sendable> {
    @MainActor
    private final class Load {
        var task: Task<Void, Never>?
        /// Callers waiting for the result that haven't been cancelled, each
        /// resumed on its own.
        var waiters: [Int: CheckedContinuation<Value?, Never>] = [:]
    }

    private var loads: [Key: Load] = [:]
    private var nextWaiterID = 0

    public init() {}

    /// How many loads are running.
    public var count: Int { loads.count }

    public func isLoading(_ key: Key) -> Bool {
        loads[key] != nil
    }

    /// Callers waiting on the load for `key` that haven't been cancelled.
    func waitingCount(for key: Key) -> Int {
        loads[key]?.waiters.count ?? 0
    }

    /// What `work` produces for `key`, run in a detached task unless a load
    /// for `key` is already running, in which case its result is shared.
    /// `nil` when `work` returns `nil` or the caller is cancelled.
    public func value(
        for key: Key,
        priority: TaskPriority? = .userInitiated,
        work: @escaping @Sendable () async -> Value?
    ) async -> Value? {
        guard !Task.isCancelled else { return nil }
        let load = loads[key] ?? start(key, priority: priority, work: work)
        let id = nextWaiterID
        nextWaiterID += 1

        let value = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Value?, Never>) in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    abandonIfUnwanted(load, key: key)
                    return
                }
                load.waiters[id] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.callerCancelled(id, of: load, key: key)
            }
        }
        return Task.isCancelled ? nil : value
    }

    private func start(_ key: Key, priority: TaskPriority?, work: @escaping @Sendable () async -> Value?) -> Load {
        let load = Load()
        loads[key] = load
        load.task = Task.detached(priority: priority) { [weak self] in
            let value = await work()
            await self?.finish(load, key: key, value: value)
        }
        return load
    }

    /// Hands the result to every caller still waiting.
    private func finish(_ load: Load, key: Key, value: Value?) {
        if loads[key] === load { loads[key] = nil }
        let waiters = load.waiters
        load.waiters = [:]
        for continuation in waiters.values {
            continuation.resume(returning: value)
        }
    }

    /// Lets a cancelled caller go at once; cancels the load when nobody is
    /// left waiting for it.
    private func callerCancelled(_ id: Int, of load: Load, key: Key) {
        guard let continuation = load.waiters.removeValue(forKey: id) else { return }
        continuation.resume(returning: nil)
        abandonIfUnwanted(load, key: key)
    }

    private func abandonIfUnwanted(_ load: Load, key: Key) {
        guard load.waiters.isEmpty else { return }
        load.task?.cancel()
        if loads[key] === load { loads[key] = nil }
    }
}
