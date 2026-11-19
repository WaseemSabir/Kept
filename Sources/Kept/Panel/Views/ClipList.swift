import KeptCore
import SwiftUI

/// The list of clips: quick-paste numbers in the gutter, pins on top above
/// a hairline, the selection marked with the highlighter. Selection moves
/// instantly and the list scrolls just enough to keep it in view.
///
/// Each row has a context menu with the clip's actions. Pins can be dragged
/// into a new order while the list shows them in their own order.
struct ClipList: View {
    let model: PanelViewModel
    let resources: PanelResources

    /// The rows' coordinate space, for working out which row a dragged pin
    /// is over.
    private static let rowSpace = "ClipList.rows"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                rows
            }
            // Selection drives scrolling; a legacy scroller would only take
            // width from the rows and push the icons off the 12 pt gutter.
            .scrollIndicators(.never)
            .onChange(of: model.selectedID) {
                guard let id = model.selectedID else { return }
                proxy.scrollTo(id)
            }
            .onChange(of: model.presentationCount) {
                guard let id = model.results.first?.id else { return }
                proxy.scrollTo(id, anchor: .top)
            }
        }
    }

    private var rows: some View {
        let sectionBreak = model.sectionBreakIndex
        let selectedID = model.selectedID
        let now = model.now
        let canReorderPins = model.canReorderPins
        return LazyVStack(spacing: 0) {
            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, clip in
                ClipRow(
                    clip: clip,
                    number: index < 9 ? index + 1 : nil,
                    isSelected: clip.id == selectedID,
                    startsSection: index == sectionBreak,
                    now: now,
                    resources: resources
                )
                .id(clip.id)
                .gesture(TapGesture(count: 2).onEnded { model.activate(clip) })
                .simultaneousGesture(TapGesture().onEnded { model.select(clip) })
                // `.subviews` keeps the taps above working when the drag is off.
                .simultaneousGesture(pinDrag(for: clip), including: canReorderPins && clip.isPinned ? .all : .subviews)
                .contextMenu { ClipContextMenu(clip: clip, model: model) }
            }
        }
        .coordinateSpace(.named(Self.rowSpace))
        .padding(.vertical, 4)
    }

    /// Dragging a pin moves it to the pinned row under the pointer as it
    /// goes; the store keeps each new order.
    private func pinDrag(for clip: Clip) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.rowSpace))
            .onChanged { drag in
                let row = Int((drag.location.y / Theme.Layout.rowHeight).rounded(.down))
                model.dragPin(clip, toRow: row)
            }
    }
}

/// A row's context menu: the same actions as the keys, for the clicked
/// clip, with their keys shown.
private struct ClipContextMenu: View {
    let clip: Clip
    let model: PanelViewModel

    var body: some View {
        Button(model.primaryActionTitle) {
            model.perform(.activate(alternate: false), on: clip)
        }
        .keyboardShortcut(.return, modifiers: [])
        Button(model.alternateActionTitle) {
            model.perform(.activate(alternate: true), on: clip)
        }
        .keyboardShortcut(.return, modifiers: .option)
        if let copyOnlyTitle = model.copyOnlyActionTitle {
            Button(copyOnlyTitle) {
                model.perform(.copyOnly, on: clip)
            }
            .keyboardShortcut(.return, modifiers: .command)
        }
        Divider()
        Button(clip.isPinned ? "Unpin" : "Pin") {
            model.perform(.togglePin, on: clip)
        }
        .keyboardShortcut("p", modifiers: .command)
        Button("Delete") {
            model.perform(.delete, on: clip)
        }
        .keyboardShortcut(.delete, modifiers: .command)
    }
}
