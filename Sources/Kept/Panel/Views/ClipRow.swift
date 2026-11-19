import KeptCore
import SwiftUI

/// One 34 pt row: quick-paste number, the clip drawn by kind, the clip's
/// age and the source app's icon.
struct ClipRow: View {
    let clip: Clip
    /// 1–9 for the first nine rows (⌘1–⌘9).
    let number: Int?
    let isSelected: Bool
    /// Draws the hairline between the pinned section and the rest.
    let startsSection: Bool
    let now: Date
    let resources: PanelResources

    var body: some View {
        HStack(spacing: 0) {
            Text(number.map(String.init) ?? "")
                .font(Theme.Typography.index)
                .foregroundStyle(Theme.Colors.inkFaint)
                .frame(width: Theme.Layout.leadingColumnWidth, alignment: .leading)
                .accessibilityHidden(true)
            ClipSummary(clip: clip, isMarked: isSelected, resources: resources)
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
        .accessibilityElement(children: .combine)
        .accessibilityValue(clip.isPinned ? "Pinned" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
