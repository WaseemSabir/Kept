/// Runs slow loads (disk reads, decoding) off the main actor, one per key
/// at a time, for callers on the main actor.
///
/// Callers asking for a key that's already loading wait for the same
/// result instead of starting another load. A caller that's cancelled gets
/// `nil`; once every caller waiting on a load has been cancelled, the load
/// itself is cancelled (it should check `Task.isCancelled`) and forgotten,
/// so the next request starts afresh. Caching results is up to the caller.
@MainActor
public final class SharedLoads<Key: Hashable & Sendable, Value: Sendable> {
    @MainActor
    private final class Load {
        let task: Task<Value?, Never>
        /// Callers waiting for the result that haven't been cancelled.
        var waiting = 0

        init(task: Task<Value?, Never>) {
            self.task = task
        }
    }

    private var loads: [Key: Load] = [:]

    public init() {}

    /// How many loads are running.
    public var count: Int { loads.count }

    public func isLoading(_ key: Key) -> Bool {
        loads[key] != nil
    }

    /// Callers waiting on the load for `key` that haven't been cancelled.
    func waitingCount(for key: Key) -> Int {
        loads[key]?.waiting ?? 0
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
        let load: Load
        if let running = loads[key] {
            load = running
        } else {
            load = Load(task: Task.detached(priority: priority, operation: work))
            loads[key] = load
        }
        load.waiting += 1

        let value = await withTaskCancellationHandler {
            await load.task.value
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.callerCancelled(load, key: key)
            }
        }
        if loads[key] === load { loads[key] = nil }
        return Task.isCancelled ? nil : value
    }

    private func callerCancelled(_ load: Load, key: Key) {
        load.waiting -= 1
        guard load.waiting <= 0 else { return }
        load.task.cancel()
        if loads[key] === load { loads[key] = nil }
    }
}
