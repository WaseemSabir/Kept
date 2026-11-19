import AppKit
import Testing
@testable import Kept

@MainActor
@Suite("Pasteboard monitor")
struct PasteboardMonitorTests {
    @Test("Reports each new copy once")
    func reportsChanges() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let monitor = PasteboardMonitor(pasteboard: pasteboard, isPaused: { false })
        var reported: [Int] = []
        monitor.onChange = { reported.append($0) }

        #expect(monitor.poll() == .unchanged)
        let first = pasteboard.simulateCopy("one")
        #expect(monitor.poll() == .changed(changeCount: first))
        #expect(monitor.poll() == .unchanged)
        let second = pasteboard.simulateCopy("two")
        #expect(monitor.poll() == .changed(changeCount: second))
        #expect(reported == [first, second])
    }

    @Test("Skips what was on the pasteboard before it started")
    func ignoresExistingContents() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.simulateCopy("from before")
        let monitor = PasteboardMonitor(pasteboard: pasteboard, isPaused: { false })
        #expect(monitor.poll() == .unchanged)
    }

    @Test("Skips Kept's own writes by change count")
    func skipsOwnWrites() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let monitor = PasteboardMonitor(pasteboard: pasteboard, isPaused: { false })
        var reported = 0
        monitor.onChange = { _ in reported += 1 }

        monitor.noteOwnWrite(changeCount: pasteboard.simulateCopy("mine"))
        #expect(monitor.poll() == .ownWrite)
        // An own write that another copy replaced before the poll is forgotten.
        monitor.noteOwnWrite(changeCount: pasteboard.simulateCopy("mine again"))
        let theirs = pasteboard.simulateCopy("theirs")
        #expect(monitor.poll() == .changed(changeCount: theirs))
        #expect(reported == 1)
    }

    @Test("Pausing and ignoring the next copy skip changes")
    func pauseAndIgnoreNext() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let pause = PauseSwitch(isOn: true)
        let monitor = PasteboardMonitor(pasteboard: pasteboard, isPaused: { pause.isOn })

        pasteboard.simulateCopy("while paused")
        #expect(monitor.poll() == .paused)

        pause.isOn = false
        monitor.ignoreNextCopy()
        #expect(monitor.isIgnoringNextCopy)
        pasteboard.simulateCopy("a password typed by hand")
        #expect(monitor.poll() == .ignoredOnce)
        #expect(!monitor.isIgnoringNextCopy)
        let next = pasteboard.simulateCopy("next")
        #expect(monitor.poll() == .changed(changeCount: next))
    }

    @Test("Ignoring the next copy can be taken back")
    func cancelIgnoreNextCopy() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let monitor = PasteboardMonitor(pasteboard: pasteboard, isPaused: { false })

        monitor.ignoreNextCopy()
        #expect(monitor.isIgnoringNextCopy)
        monitor.cancelIgnoreNextCopy()
        #expect(!monitor.isIgnoringNextCopy)
        let next = pasteboard.simulateCopy("kept after all")
        #expect(monitor.poll() == .changed(changeCount: next))
    }

    @Test("Tells capture when the previous poll ran")
    func previousPollTime() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let monitor = PasteboardMonitor(pasteboard: pasteboard, isPaused: { false })
        #expect(monitor.previousPollTime == nil)

        let beforeFirst = AppActivationTracker.now()
        monitor.poll()
        let afterFirst = AppActivationTracker.now()
        var windowStart: Double?
        monitor.onChange = { _ in windowStart = monitor.previousPollTime }
        pasteboard.simulateCopy("copied between polls")
        monitor.poll()

        // The change happened after the first poll, which is when the window opens.
        let start = try #require(windowStart)
        #expect(start >= beforeFirst)
        #expect(start <= afterFirst)
    }
}

/// Stands in for `Preferences.isPaused`.
@MainActor
private final class PauseSwitch {
    var isOn: Bool

    init(isOn: Bool) {
        self.isOn = isOn
    }
}
