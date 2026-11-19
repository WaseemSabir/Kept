import Foundation
import Testing
@testable import Kept
import KeptCore

@MainActor
@Suite("Panel pins and row actions")
struct PanelPinsAndRowActionsTests {
    let directory: URL

    init() throws {
        directory = try makeTemporaryDirectory()
    }

    /// "one" … "five", newest first, with "three", "four" and "five" pinned
    /// in that order: the list reads three, four, five, one, two.
    private func makeModel(paster: RecordingPaster = RecordingPaster()) throws -> (PanelViewModel, HistoryStore) {
        let store = try makeStore(in: directory, texts: ["one", "two", "three", "four", "five"])
        for title in ["three", "four", "five"] {
            let clip = try #require(store.recent.first { $0.title == title })
            try store.pin(clip.id)
        }
        let model = PanelViewModel(store: store, paster: paster)
        model.prepareForShow()
        return (model, store)
    }

    private func clip(_ title: String, in model: PanelViewModel) throws -> Clip {
        try #require(model.results.first { $0.title == title })
    }

    // MARK: Moving pins

    @Test("⌥⌘↑ / ⌥⌘↓ move the selected pin and keep it selected")
    func keyboardMoves() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store) = try makeModel()
        #expect(model.results.map(\.title) == ["three", "four", "five", "one", "two"])

        model.select(index: 0)
        model.perform(.movePin(by: 1))
        #expect(store.pinned.map(\.title) == ["four", "three", "five"])
        #expect(model.selectedClip?.title == "three")
        #expect(model.selectedIndex == 1)

        model.perform(.movePin(by: 1))
        model.perform(.movePin(by: 1))
        #expect(store.pinned.map(\.title) == ["four", "five", "three"])

        model.perform(.movePin(by: -1))
        #expect(store.pinned.map(\.title) == ["four", "three", "five"])
        #expect(model.results.map(\.title) == ["four", "three", "five", "one", "two"])
        #expect(model.selectedIndex == 1)
    }

    @Test("Only pins move, and only while the list shows them in order")
    func movingNeedsOrderedPins() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store) = try makeModel()
        #expect(model.canReorderPins)

        model.select(index: 3)
        model.perform(.movePin(by: -1))
        #expect(store.pinned.map(\.title) == ["three", "four", "five"])

        model.filter = .pinned
        #expect(model.canReorderPins)
        model.select(index: 2)
        model.perform(.movePin(by: -2))
        #expect(store.pinned.map(\.title) == ["five", "three", "four"])

        model.filter = .text
        #expect(!model.canReorderPins)
        model.filter = .all
        model.query = "f"
        #expect(!model.canReorderPins)
        model.select(index: 0)
        model.perform(.movePin(by: 1))
        #expect(store.pinned.map(\.title) == ["five", "three", "four"])
    }

    @Test("Dragging a pin moves it to the pinned row under the pointer")
    func dragging() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, store) = try makeModel()
        let five = try clip("five", in: model)

        model.dragPin(five, toRow: 0)
        #expect(store.pinned.map(\.title) == ["five", "three", "four"])
        #expect(model.selectedClip?.title == "five")

        // Below the pinned section: the last pinned place.
        model.dragPin(five, toRow: 4)
        #expect(store.pinned.map(\.title) == ["three", "four", "five"])
        model.dragPin(five, toRow: -3)
        #expect(store.pinned.map(\.title) == ["five", "three", "four"])

        // Unpinned clips don't move.
        model.dragPin(try clip("one", in: model), toRow: 0)
        #expect(store.pinned.map(\.title) == ["five", "three", "four"])
        #expect(model.results.map(\.title) == ["five", "three", "four", "one", "two"])

        // Nor do pins while searching.
        model.query = "three"
        model.dragPin(try clip("three", in: model), toRow: 2)
        #expect(store.pinned.map(\.title) == ["five", "three", "four"])
    }

    // MARK: Context menu

    @Test("The context menu acts on the clicked clip")
    func contextMenu() throws {
        defer { removeTemporaryDirectory(directory) }
        let paster = RecordingPaster()
        let (model, store) = try makeModel(paster: paster)
        let log = EventLog()
        model.onDismiss = { log.events.append("dismiss") }

        model.perform(.activate(alternate: true), on: try clip("two", in: model))
        #expect(model.selectedClip?.title == "two")
        model.perform(.copyOnly, on: try clip("one", in: model))
        model.perform(.activate(alternate: false), on: try clip("four", in: model))
        #expect(paster.pastes == [
            RecordingPaster.Paste(title: "two", request: .paste(alternate: true)),
            RecordingPaster.Paste(title: "one", request: .copyOnly),
            RecordingPaster.Paste(title: "four", request: .paste(alternate: false)),
        ])
        #expect(log.events == ["dismiss", "dismiss", "dismiss"])

        model.perform(.togglePin, on: try clip("one", in: model))
        #expect(store.pinned.map(\.title) == ["three", "four", "five", "one"])
        model.perform(.togglePin, on: try clip("four", in: model))
        #expect(store.pinned.map(\.title) == ["three", "five", "one"])

        model.perform(.delete, on: try clip("two", in: model))
        #expect(!store.recent.contains { $0.title == "two" })
        #expect(model.notice == nil)
    }

    @Test("⌘, opens Settings")
    func openSettings() throws {
        defer { removeTemporaryDirectory(directory) }
        let (model, _) = try makeModel()
        let log = EventLog()
        model.onOpenSettings = { log.events.append("settings") }
        #expect(model.perform(.openSettings))
        #expect(log.events == ["settings"])
    }
}
