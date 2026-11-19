import AppKit
import Testing
@testable import Kept

@MainActor
@Suite("Status menu")
struct StatusMenuTests {
    @Test("The pause item says what choosing it does")
    func pauseTitle() {
        #expect(StatusMenuState(isPaused: false).pauseTitle == "Pause capture")
        #expect(StatusMenuState(isPaused: true).pauseTitle == "Resume capture")
    }

    @Test("Ignore next copy is unavailable while paused and checked while armed")
    func ignoreNextCopy() {
        let armed = StatusMenuState(isPaused: false, isIgnoringNextCopy: true)
        #expect(armed.canIgnoreNextCopy)
        #expect(armed.isIgnoreNextCopyChecked)

        let paused = StatusMenuState(isPaused: true, isIgnoringNextCopy: true)
        #expect(!paused.canIgnoreNextCopy)
        #expect(!paused.isIgnoreNextCopyChecked)

        let noHistory = StatusMenuState(isHistoryAvailable: false)
        #expect(!noHistory.canIgnoreNextCopy)
        #expect(!noHistory.canClearHistory)
        #expect(StatusMenuState().canClearHistory)
    }

    @Test("The menu lists its items in order, follows the state and runs its actions")
    func menu() throws {
        let log = EventLog()
        let statusMenu = StatusMenu(actions: StatusMenu.Actions(
            openPanel: { log.events.append("open") },
            togglePause: { log.events.append("pause") },
            ignoreNextCopy: { log.events.append("ignore") },
            clearHistory: { log.events.append("clear") },
            openSettings: { log.events.append("settings") },
            quit: { log.events.append("quit") }
        ))
        let items = statusMenu.menu.items.filter { !$0.isSeparatorItem }
        #expect(items.map(\.title) == [
            "Open Kept", "Pause capture", "Ignore next copy", "Clear history…", "Settings…", "Quit Kept",
        ])
        #expect(statusMenu.openItem.keyEquivalent == "v")
        #expect(statusMenu.openItem.keyEquivalentModifierMask == [.shift, .command])
        #expect(statusMenu.settingsItem.keyEquivalent == ",")
        #expect(statusMenu.settingsItem.keyEquivalentModifierMask == .command)
        #expect(statusMenu.quitItem.keyEquivalent == "q")

        statusMenu.update(StatusMenuState(isPaused: true, isIgnoringNextCopy: true))
        #expect(statusMenu.pauseItem.title == "Resume capture")
        #expect(!statusMenu.ignoreNextCopyItem.isEnabled)
        #expect(statusMenu.ignoreNextCopyItem.state == .off)

        statusMenu.update(StatusMenuState(isPaused: false, isIgnoringNextCopy: true))
        #expect(statusMenu.pauseItem.title == "Pause capture")
        #expect(statusMenu.ignoreNextCopyItem.isEnabled)
        #expect(statusMenu.ignoreNextCopyItem.state == .on)

        statusMenu.update(StatusMenuState(isHistoryAvailable: false))
        #expect(!statusMenu.clearHistoryItem.isEnabled)

        for item in items {
            let target = try #require(item.target as? NSObject)
            let action = try #require(item.action)
            _ = target.perform(action, with: item)
        }
        #expect(log.events == ["open", "pause", "ignore", "clear", "settings", "quit"])
    }
}
