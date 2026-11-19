import AppKit
import Testing
@testable import Kept
import KeptCore

@MainActor
@Suite("Capture service")
struct CaptureServiceTests {
    @Test("Records a copy, and the same copy again as one clip")
    func recordsCopies() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let store = try HistoryStore(directory: directory)
        let service = CaptureService(pasteboard: pasteboard, store: store, settings: { CaptureSettings() })

        pasteboard.simulateCopy("Meeting notes for Thursday", markers: [.source])
        service.captureCurrentContents()
        await service.waitUntilIdle()
        #expect(store.recent.map(\.title) == ["Meeting notes for Thursday"])
        #expect(store.recent.first?.sourceBundleID == "com.apple.TextEdit")

        pasteboard.simulateCopy("Meeting notes for Thursday")
        service.captureCurrentContents()
        await service.waitUntilIdle()
        #expect(store.recent.count == 1)
        #expect(store.recent.first?.copyCount == 2)
    }

    @Test("Concealed copies never reach the history")
    func skipsConcealed() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let store = try HistoryStore(directory: directory)
        let service = CaptureService(pasteboard: pasteboard, store: store, settings: { CaptureSettings() })

        pasteboard.simulateCopy("hunter2", markers: [.concealed])
        service.captureCurrentContents()
        await service.waitUntilIdle()
        #expect(store.recent.isEmpty)
    }

    @Test("A TIFF screenshot is stored as PNG with its size")
    func storesTIFFAsPNG() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let store = try HistoryStore(directory: directory)
        let service = CaptureService(pasteboard: pasteboard, store: store, settings: { CaptureSettings() })

        pasteboard.clearContents()
        pasteboard.setData(try encodedImage(width: 30, height: 20, type: "public.tiff"), forType: .tiff)
        service.captureCurrentContents()
        await service.waitUntilIdle()

        let clip = try #require(store.recent.first)
        #expect(clip.kind == .image)
        #expect(clip.title == "Image 30 × 20")
        #expect(clip.metadata.imageType == .png)
        let types = try store.representations(for: clip.id).flatMap(\.types)
        #expect(types == [.png])
    }

    // MARK: Builds finishing late

    @Test("Builds that finish out of order are recorded by when their copies were seen")
    func outOfOrderBuilds() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let slow = harness.pasteboard.simulateCopy("copied first")
        await harness.gate.hold(slow)
        harness.service.captureCurrentContents()
        harness.pasteboard.simulateCopy("copied second")
        harness.service.captureCurrentContents()

        await waitUntil { harness.store.recent.count == 1 }
        #expect(harness.store.recent.map(\.title) == ["copied second"])
        await harness.gate.release(slow)
        await harness.service.waitUntilIdle()
        #expect(harness.store.recent.map(\.title) == ["copied second", "copied first"])
    }

    @Test("A slow build doesn't move a newer copy of the same content back in time")
    func staleDuplicate() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        let slow = harness.pasteboard.simulateCopy("same words")
        await harness.gate.hold(slow)
        harness.service.captureCurrentContents()
        harness.pasteboard.simulateCopy("same words")
        harness.service.captureCurrentContents()

        await waitUntil { harness.store.recent.count == 1 }
        let recorded = try #require(harness.store.recent.first)
        await harness.gate.release(slow)
        await harness.service.waitUntilIdle()
        #expect(harness.store.recent.count == 1)
        #expect(harness.store.recent.first?.copyCount == 1)
        #expect(harness.store.recent.first?.lastCopiedAt == recorded.lastCopiedAt)
    }

    @Test("A build that finishes after the history is cleared is dropped, blob files and all")
    func buildAfterClear() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        // Big enough to become a blob file.
        let held = harness.pasteboard.simulateCopy(String(repeating: "Lorem ipsum ", count: 8_000))
        await harness.gate.hold(held)
        harness.service.captureCurrentContents()
        await waitUntil { await harness.gate.hasArrived(held) }

        try harness.store.clearAll()
        await harness.gate.release(held)
        await harness.service.waitUntilIdle()
        #expect(harness.store.recent.isEmpty)
        #expect(try harness.blobFiles().isEmpty)
    }

    @Test("A build that finishes after pausing, excluding its app or turning its kind off is dropped")
    func settingsChangedDuringBuild() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }

        /// Captures what's on the pasteboard, changing the settings while
        /// the build is held back.
        func capture(changingSettings change: (inout CaptureSettings) -> Void) async {
            let held = harness.pasteboard.changeCount
            await harness.gate.hold(held)
            harness.service.captureCurrentContents()
            await waitUntil { await harness.gate.hasArrived(held) }
            change(&harness.settings.value)
            await harness.gate.release(held)
            await harness.service.waitUntilIdle()
            harness.settings.value = CaptureSettings()
        }

        harness.pasteboard.simulateCopy("copied before pausing")
        await capture { $0.isPaused = true }
        #expect(harness.store.recent.isEmpty)

        harness.pasteboard.simulateCopy("from TextEdit", markers: [.source])
        await capture { $0.excludedBundleIDs.insert("com.apple.textedit") }
        #expect(harness.store.recent.isEmpty)

        harness.pasteboard.clearContents()
        harness.pasteboard.setData(try encodedImage(width: 4, height: 4, type: "public.png"), forType: .png)
        await capture { $0.captureImages = false }
        #expect(harness.store.recent.isEmpty)

        // Unchanged settings: recorded.
        harness.pasteboard.simulateCopy("kept")
        await capture { _ in }
        #expect(harness.store.recent.map(\.title) == ["kept"])
    }

    @Test("Deleting a clip while a copy of it builds keeps it deleted; a later copy brings it back")
    func deleteDuringBuild() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        harness.pasteboard.simulateCopy("delete me")
        harness.service.captureCurrentContents()
        await harness.service.waitUntilIdle()
        let clip = try #require(harness.store.recent.first)

        // Copied again, then deleted while that copy is still building.
        let held = harness.pasteboard.simulateCopy("delete me")
        await harness.gate.hold(held)
        harness.service.captureCurrentContents()
        await waitUntil { await harness.gate.hasArrived(held) }
        try harness.store.delete(clip.id)
        await harness.gate.release(held)
        await harness.service.waitUntilIdle()
        #expect(harness.store.recent.isEmpty)

        harness.pasteboard.simulateCopy("delete me")
        harness.service.captureCurrentContents()
        await harness.service.waitUntilIdle()
        #expect(harness.store.recent.map(\.title) == ["delete me"])
    }

    @Test("While every build is busy, a newer copy replaces the one waiting, and the newest is recorded")
    func coalescesWaitingCopies() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        var held: [Int] = []
        for index in 1...CaptureService.maxBuildsInFlight {
            let copy = harness.pasteboard.simulateCopy("busy \(index)")
            await harness.gate.hold(copy)
            held.append(copy)
            harness.service.captureCurrentContents()
        }
        harness.pasteboard.simulateCopy("replaced")
        harness.service.captureCurrentContents()
        harness.pasteboard.simulateCopy("newest")
        harness.service.captureCurrentContents()
        await waitUntil { await harness.gate.arrivedCount == CaptureService.maxBuildsInFlight }
        #expect(await harness.gate.arrivedCount == CaptureService.maxBuildsInFlight, "no third build runs")

        for copy in held {
            await harness.gate.release(copy)
        }
        await harness.service.waitUntilIdle()
        let busy = (1...CaptureService.maxBuildsInFlight).reversed().map { "busy \($0)" }
        #expect(harness.store.recent.map(\.title) == ["newest"] + busy)
        #expect(await harness.gate.arrivedCount == CaptureService.maxBuildsInFlight + 1)
    }

    // MARK: Reading

    @Test("A read that saw the pasteboard change records nothing and builds nothing")
    func changedDuringRead() async throws {
        let harness = try Harness(read: { _, _, _ in .changedDuringRead })
        defer { harness.tearDown() }
        harness.pasteboard.simulateCopy("half read")
        harness.service.captureCurrentContents()
        await harness.service.waitUntilIdle()
        #expect(harness.store.recent.isEmpty)
        #expect(await harness.gate.arrivedCount == 0)
    }

    @Test("A copy whose source marker names an excluded app is never read")
    func excludedBySourceMarker() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        harness.pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("vault entry", forType: .string)
        item.setString("com.bitwarden.desktop", forType: NSPasteboard.PasteboardType(PasteboardType.source.rawValue))
        harness.pasteboard.writeObjects([item])

        harness.service.captureCurrentContents()
        await harness.service.waitUntilIdle()
        #expect(harness.store.recent.isEmpty)
        #expect(await harness.gate.arrivedCount == 0)
    }

    @Test("A copy is skipped when an excluded app was in front at any moment since the last poll")
    func excludedAppInTheWindow() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        // The password manager came up, copied, and gave focus back to
        // Safari, all between two polls.
        let windowStart = AppActivationTracker.now()
        harness.activations.record("com.1password.1password", at: windowStart)
        harness.activations.record("com.apple.Safari", at: AppActivationTracker.now())
        harness.pasteboard.simulateCopy("one-time password")
        harness.service.captureCurrentContents(since: windowStart)
        await harness.service.waitUntilIdle()
        #expect(harness.store.recent.isEmpty)
        #expect(await harness.gate.arrivedCount == 0)

        // The next window opens with Safari in front.
        harness.pasteboard.simulateCopy("a link from Safari")
        harness.service.captureCurrentContents(since: AppActivationTracker.now())
        await harness.service.waitUntilIdle()
        #expect(harness.store.recent.map(\.title) == ["a link from Safari"])
    }

    @Test("A copy is dropped when an excluded app's activation is logged just after the poll")
    func excludedAppLoggedAfterThePoll() async throws {
        let harness = try Harness()
        defer { harness.tearDown() }
        harness.activations.record("com.apple.Safari", at: AppActivationTracker.now())
        let windowStart = AppActivationTracker.now()
        harness.pasteboard.simulateCopy("one-time password")
        harness.service.captureCurrentContents(since: windowStart)
        // The main thread was busy: the password manager came up, copied
        // and gave focus back before the poll, but its notifications were
        // handled after it.
        harness.activations.record("com.1password.1password", at: AppActivationTracker.now())
        harness.activations.record("com.apple.Safari", at: AppActivationTracker.now())
        await harness.service.waitUntilIdle()
        #expect(harness.store.recent.isEmpty)
    }
}

// MARK: Helpers

/// A capture service on a private pasteboard and a temporary history, with
/// settings to change and builds to hold back.
@MainActor
private final class Harness {
    @MainActor
    final class SettingsBox {
        var value = CaptureSettings()
    }

    let directory: URL
    let pasteboard: NSPasteboard
    let store: HistoryStore
    let gate: BuildGate
    let activations: AppActivationTracker
    let settings: SettingsBox
    let service: CaptureService

    init(read: CaptureService.Read? = nil) throws {
        let directory = try makeTemporaryDirectory()
        let pasteboard = makePasteboard()
        let store = try HistoryStore(directory: directory)
        let gate = BuildGate()
        let activations = AppActivationTracker(workspace: nil)
        let settings = SettingsBox()
        self.directory = directory
        self.pasteboard = pasteboard
        self.store = store
        self.gate = gate
        self.activations = activations
        self.settings = settings
        service = CaptureService(
            pasteboard: pasteboard,
            store: store,
            settings: { settings.value },
            activations: activations,
            read: read,
            willBuild: { snapshot in await gate.pass(snapshot) }
        )
    }

    func blobFiles() throws -> [String] {
        let blobs = directory.appendingPathComponent("blobs")
        return try FileManager.default.contentsOfDirectory(atPath: blobs.path).filter { !$0.hasPrefix(".") }
    }

    func tearDown() {
        pasteboard.releaseGlobally()
        removeTemporaryDirectory(directory)
    }
}

/// Holds builds back, by the change count of their copy, until released,
/// so a test decides the order builds finish in.
private actor BuildGate {
    private var held: Set<Int> = []
    private var arrived: [Int] = []

    var arrivedCount: Int { arrived.count }

    func hold(_ changeCount: Int) {
        held.insert(changeCount)
    }

    func release(_ changeCount: Int) {
        held.remove(changeCount)
    }

    func hasArrived(_ changeCount: Int) -> Bool {
        arrived.contains(changeCount)
    }

    /// Called before each build; returns once the build may go on.
    func pass(_ snapshot: PasteboardSnapshot) async {
        arrived.append(snapshot.changeCount)
        while held.contains(snapshot.changeCount) {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

/// Waits until `condition` holds, for up to 30 seconds (other tests share
/// the main actor).
@MainActor
private func waitUntil(_ condition: @MainActor () async -> Bool) async {
    for _ in 0..<3_000 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Timed out waiting for a condition")
}
