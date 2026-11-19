import KeptCore
import SwiftUI

/// The list of clips: quick-paste numbers in the gutter, pins on top above
/// a hairline, the selection marked with the highlighter. Selection moves
/// instantly and the list scrolls just enough to keep it in view.
///
/// The list itself never reads the selection: each row does, so an arrow
/// key updates the rows on screen instead of rebuilding the whole list
/// (which can hold 10,000 clips).
///
/// Each row has a context menu with the clip's actions. Pins can be dragged
/// into a new order while the list shows them in their own order. The row
/// being renamed takes no taps or drags, so clicks reach its name field.
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
            .background {
                SelectionScroller(model: model, proxy: proxy)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clips")
    }

    private var rows: some View {
        let sectionBreak = model.sectionBreakIndex
        let now = model.now
        let canReorderPins = model.canReorderPins
        let matchTokens = model.matchTokens
        let renamingID = model.renamingID
        return LazyVStack(spacing: 0) {
            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, clip in
                let takesTaps: GestureMask = clip.id == renamingID ? .subviews : .all
                ClipRow(
                    clip: clip,
                    model: model,
                    number: index < 9 ? index + 1 : nil,
                    startsSection: index == sectionBreak,
                    matchTokens: matchTokens,
                    now: now,
                    resources: resources
                )
                .id(clip.id)
                .gesture(TapGesture(count: 2).onEnded { model.activate(clip) }, including: takesTaps)
                .simultaneousGesture(TapGesture().onEnded { model.select(clip) }, including: takesTaps)
                // `.subviews` keeps the taps above working when the drag is off.
                .simultaneousGesture(
                    pinDrag(for: clip),
                    including: canReorderPins && clip.isPinned && clip.id != renamingID ? .all : .subviews
                )
                .contextMenu { ClipContextMenu(clip: clip, model: model) }
                .accessibilityActions {
                    // VoiceOver's way to reorder pins, besides ⌥⌘↑ / ⌥⌘↓.
                    if canReorderPins && clip.isPinned {
                        Button("Move up") { model.perform(.movePin(by: -1), on: clip) }
                        Button("Move down") { model.perform(.movePin(by: 1), on: clip) }
                    }
                }
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

/// Scrolls the selected row into view whenever it moves (`scrollToken`),
/// and back to the top when the panel opens. A view of its own, so reading
/// the selection doesn't make the whole list draw again.
private struct SelectionScroller: View {
    let model: PanelViewModel
    let proxy: ScrollViewProxy

    var body: some View {
        Color.clear
            .onChange(of: model.scrollToken) {
                guard let id = model.selectedID else { return }
                proxy.scrollTo(id)
            }
            .onChange(of: model.presentationCount) {
                guard let id = model.results.first?.id else { return }
                proxy.scrollTo(id, anchor: .top)
            }
            .accessibilityHidden(true)
    }
}

/// A row's context menu: the same actions as the keys, for the clicked
/// clip, with their keys shown (`ClipMenu`).
private struct ClipContextMenu: View {
    let clip: Clip
    let model: PanelViewModel

    var body: some View {
        let sections = model.menuSections(for: clip)
        ForEach(Array(sections.enumerated()), id: \.offset) { index, items in
            if index > 0 { Divider() }
            ForEach(items, id: \.title) { item in
                Button(item.title) {
                    model.perform(item.command, on: clip)
                }
                .keyboardShortcut(Self.shortcut(for: item.command))
            }
        }
    }

    /// The key each command has in the panel, shown beside it.
    private static func shortcut(for command: PanelCommand) -> KeyboardShortcut? {
        switch command {
        case .activate(alternate: false): KeyboardShortcut(.return, modifiers: [])
        case .activate(alternate: true): KeyboardShortcut(.return, modifiers: .option)
        case .copyOnly: KeyboardShortcut(.return, modifiers: .command)
        case .togglePin: KeyboardShortcut("p", modifiers: .command)
        case .beginRename: KeyboardShortcut("r", modifiers: .command)
        case .beginTextEdit: KeyboardShortcut("e", modifiers: .command)
        case .delete: KeyboardShortcut(.delete, modifiers: .command)
        default: nil
        }
    }
}
