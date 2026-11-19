import SwiftUI

/// The panel's content: search bar, the clip list beside the preview, and a
/// footer of key hints (or the inline confirmation for clearing history).
struct PanelView: View {
    let model: PanelViewModel
    let resources: PanelResources
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(model: model)
            Hairline()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Hairline()
            if model.isConfirmingClear {
                ClearConfirmationBar(model: model)
            } else {
                PanelFooter(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(PanelAppearEffect(trigger: model.presentationCount, isEnabled: !reduceMotion))
        .background {
            // The material turns opaque under Reduce Transparency; the
            // panel doesn't count on it and draws the window background
            // (outside the appear effect, so it never scales with it).
            if reduceTransparency {
                Theme.Colors.panelBackground.ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let emptyState = model.emptyState, emptyState.spansPanel {
            EmptyStateView(state: emptyState)
        } else {
            HStack(spacing: 0) {
                Group {
                    if let emptyState = model.emptyState {
                        EmptyStateView(state: emptyState)
                    } else {
                        ClipList(model: model, resources: resources)
                    }
                }
                .frame(width: Theme.Layout.listWidth)
                Hairline(axis: .vertical)
                PreviewPane(model: model, resources: resources)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// The panel's entrance: a ≤120 ms settle from 98% scale (the window fades
/// in alongside, in AppKit). Off under Reduce Motion.
private struct PanelAppearEffect: ViewModifier {
    let trigger: Int
    let isEnabled: Bool

    func body(content: Content) -> some View {
        let startScale = Theme.Motion.panelAppearScale
        let duration = Theme.Motion.panelAppearDuration
        if isEnabled {
            content.keyframeAnimator(initialValue: CGFloat(1), trigger: trigger) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    MoveKeyframe(startScale)
                    CubicKeyframe(CGFloat(1), duration: duration)
                }
            }
        } else {
            content
        }
    }
}
