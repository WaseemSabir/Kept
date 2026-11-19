import Testing
@testable import KeptCore

/// Counts how often something ran, from any task.
private actor Counter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

/// Holds loads back until the test opens it, so no load can finish before
/// every caller the test wants has joined it.
private actor Latch {
    private var isOpen = false

    func open() {
        isOpen = true
    }

    /// Returns once the latch is open, or `false` straight away if the
    /// task is cancelled first.
    func wait() async -> Bool {
        while !isOpen {
            guard !Task.isCancelled else { return false }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }
}

/// Waits on the main actor without spinning it hot.
@MainActor
private func pause() async {
    try? await Task.sleep(for: .milliseconds(1))
}

@MainActor
@Suite("Shared loads")
struct SharedLoadsTests {
    @Test("Callers asking for the same key share one load")
    func sharesOneLoad() async {
        let loads = SharedLoads<String, Int>()
        let runs = Counter()
        let latch = Latch()
        let work: @Sendable () async -> Int? = {
            await runs.increment()
            return await latch.wait() ? 7 : nil
        }
        let first = Task { @MainActor in await loads.value(for: "a", work: work) }
        while !loads.isLoading("a") { await pause() }
        let second = Task { @MainActor in await loads.value(for: "a", work: work) }
        while loads.waitingCount(for: "a") < 2 { await pause() }
        await latch.open()

        #expect(await first.value == 7)
        #expect(await second.value == 7)
        #expect(await runs.value == 1)
        #expect(loads.count == 0)
    }

    @Test("Cancelling every caller cancels the load; the next request starts afresh")
    func cancelsUnwantedLoads() async {
        let loads = SharedLoads<String, Int>()
        let latch = Latch()
        let finished = Counter()
        let caller = Task { @MainActor in
            await loads.value(for: "a") {
                guard await latch.wait() else { return nil }
                await finished.increment()
                return 1
            }
        }
        while !loads.isLoading("a") { await pause() }
        caller.cancel()

        #expect(await caller.value == nil)
        while loads.isLoading("a") { await pause() }
        await latch.open()
        #expect(await finished.value == 0)
        #expect(await loads.value(for: "a") { 2 } == 2)
    }

    @Test("A cancelled caller gets nil while the others still get the value")
    func cancelledCallerOnly() async {
        let loads = SharedLoads<String, Int>()
        let latch = Latch()
        let work: @Sendable () async -> Int? = {
            // Returns nothing if the shared load itself was cancelled.
            await latch.wait() ? 3 : nil
        }
        let leaving = Task { @MainActor in await loads.value(for: "a", work: work) }
        while !loads.isLoading("a") { await pause() }
        let staying = Task { @MainActor in await loads.value(for: "a", work: work) }
        while loads.waitingCount(for: "a") < 2 { await pause() }
        leaving.cancel()
        while loads.waitingCount(for: "a") > 1 { await pause() }
        await latch.open()

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
