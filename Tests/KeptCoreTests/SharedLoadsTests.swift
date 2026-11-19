import Testing
@testable import KeptCore

/// Counts how often something ran, from any task.
private actor Counter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

@MainActor
@Suite("Shared loads")
struct SharedLoadsTests {
    @Test("Callers asking for the same key share one load")
    func sharesOneLoad() async {
        let loads = SharedLoads<String, Int>()
        let runs = Counter()
        let work: @Sendable () async -> Int? = {
            await runs.increment()
            try? await Task.sleep(for: .milliseconds(200))
            return 7
        }
        let first = Task { @MainActor in await loads.value(for: "a", work: work) }
        while !loads.isLoading("a") { await Task.yield() }
        let second = Task { @MainActor in await loads.value(for: "a", work: work) }
        while loads.waitingCount(for: "a") < 2 { await Task.yield() }

        #expect(await first.value == 7)
        #expect(await second.value == 7)
        #expect(await runs.value == 1)
        #expect(loads.count == 0)
    }

    @Test("Cancelling every caller cancels the load; the next request starts afresh")
    func cancelsUnwantedLoads() async {
        let loads = SharedLoads<String, Int>()
        let finished = Counter()
        let caller = Task { @MainActor in
            await loads.value(for: "a") {
                do {
                    try await Task.sleep(for: .seconds(10))
                } catch {
                    return nil
                }
                await finished.increment()
                return 1
            }
        }
        while !loads.isLoading("a") { await Task.yield() }
        caller.cancel()

        #expect(await caller.value == nil)
        #expect(await finished.value == 0)
        while loads.isLoading("a") { await Task.yield() }
        #expect(await loads.value(for: "a") { 2 } == 2)
    }

    @Test("A cancelled caller gets nil while the others still get the value")
    func cancelledCallerOnly() async {
        let loads = SharedLoads<String, Int>()
        let work: @Sendable () async -> Int? = {
            try? await Task.sleep(for: .milliseconds(200))
            return 3
        }
        let leaving = Task { @MainActor in await loads.value(for: "a", work: work) }
        while !loads.isLoading("a") { await Task.yield() }
        let staying = Task { @MainActor in await loads.value(for: "a", work: work) }
        while loads.waitingCount(for: "a") < 2 { await Task.yield() }
        leaving.cancel()

        #expect(await leaving.value == nil)
        #expect(await staying.value == 3)
    }

    @Test("A caller that's already cancelled starts nothing")
    func alreadyCancelled() async {
        let loads = SharedLoads<String, Int>()
        let runs = Counter()
        let caller = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await loads.value(for: "a") {
                await runs.increment()
                return 1
            }
        }
        #expect(await caller.value == nil)
        #expect(await runs.value == 0)
        #expect(loads.count == 0)
    }
}
