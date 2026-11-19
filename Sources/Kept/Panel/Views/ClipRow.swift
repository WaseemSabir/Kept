import KeptCore
import SwiftUI

/// One 34 pt row: quick-paste number, the clip drawn by kind, the clip's
/// age and the source app's icon.
///
/// The row reads the selection itself, so moving it only updates the rows
/// on screen. To VoiceOver a row is one element: a sentence describing the
/// clip, selected or not, that pastes when activated.
struct ClipRow: View {
    let clip: Clip
    let model: PanelViewModel
    /// 1–9 for the first nine rows (⌘1–⌘9).
    let number: Int?
    /// Draws the hairline between the pinned section and the rest.
    let startsSection: Bool
    /// The query's words, set in a heavier weight where they match.
    let matchTokens: [String]
    let now: Date
    let resources: PanelResources

    var body: some View {
        let isSelected = model.selectedID == clip.id
        HStack(spacing: 0) {
            Text(number.map(String.init) ?? "")
                .font(Theme.Typography.index)
                .foregroundStyle(Theme.Colors.inkFaint)
                .frame(width: Theme.Layout.leadingColumnWidth, alignment: .leading)
                .accessibilityHidden(true)
            ClipSummary(clip: clip, isMarked: isSelected, matchTokens: matchTokens, resources: resources)
                .layoutPriority(1)
            Spacer(minLength: Theme.Spacing.gutter)
            // The age sits against the icon, and the icons form one column
            // on the trailing edge, however long the age is.
            Text(AgeFormatter.shortAge(of: clip.lastCopiedAt, now: now))
                .font(Theme.Typography.rowMeta)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.inkMuted)
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, Theme.Spacing.metaGap)
            sourceIcon
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .frame(height: Theme.Layout.rowHeight)
        .background(alignment: .leading) {
            if clip.isPinned { PinNotch() }
        }
        .overlay(alignment: .top) {
            if startsSection {
                Hairline().padding(.horizontal, Theme.Spacing.gutter)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel(for: clip))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        // The default action pastes, like ⏎ or a double-click.
        .accessibilityAction { model.activate(clip) }
        .accessibilityAction(named: model.primaryActionTitle) { model.activate(clip) }
        .accessibilityAction(named: model.alternateActionTitle) {
            model.perform(.activate(alternate: true), on: clip)
        }
        .accessibilityAction(named: clip.isPinned ? "Unpin" : "Pin") { model.perform(.togglePin, on: clip) }
        .accessibilityAction(named: "Delete") { model.perform(.delete, on: clip) }
    }

    @ViewBuilder
    private var sourceIcon: some View {
        let size = Theme.Layout.sourceIconSize
        if let bundleID = clip.sourceBundleID, let icon = resources.icons.appIcon(for: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityLabel(resources.icons.appName(for: bundleID) ?? bundleID)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

/// The marker-colored notch on the leading edge of a pinned row.
private struct PinNotch: View {
    var body: some View {
        MarkerShape(slant: 0, cornerRadius: 1.5)
            .fill(Theme.Colors.markerNotch)
            .frame(width: 3, height: 14)
            .padding(.leading, 4)
            .accessibilityHidden(true)
    }
}
