import KeptCore
import SwiftUI

/// The list of clips: quick-paste numbers in the gutter, pins on top above
/// a hairline, the selection marked with the highlighter. Selection moves
/// instantly and the list scrolls just enough to keep it in view.
struct ClipList: View {
    let model: PanelViewModel
    let resources: PanelResources

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
            }
        }
        .padding(.vertical, 4)
    }
}
