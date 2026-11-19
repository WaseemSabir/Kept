import AppKit

/// Shows the copy-only hint: a small, quiet HUD near where the panel was
/// (or at the bottom of the active screen) that says "Copied. Press ⌘V to
/// paste." and goes away by itself.
///
/// It never takes the keyboard. It fades in and out (not under Reduce
/// Motion), stays while the pointer is over it, and VoiceOver announces
/// it, since it never takes focus.
@MainActor
final class PasteHintController: PasteHintPresenting {
    private let osMajorVersion: Int
    private let openSettings: @MainActor () -> Void
    private var panel: HintPanel?
    /// The pending auto-dismiss or fade-out.
    private var lifecycle: Task<Void, Never>?
    private var isHovering = false
    /// Time ran out while the pointer was over the hint.
    private var isOverdue = false

    init(
        osMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        openSettings: @escaping @MainActor () -> Void
    ) {
        self.osMajorVersion = osMajorVersion
        self.openSettings = openSettings
    }

    func show(_ hint: PastePlan.Hint, anchor: CGRect?) {
        lifecycle?.cancel()
        isHovering = false
        isOverdue = false

        let panel = panel ?? HintPanel()
        self.panel = panel
        let size = panel.setContent(PasteHintView(
            hint: hint,
            permissionDetail: PasteHintCopy.permissionDetail(osMajorVersion: osMajorVersion),
            onAllow: { [weak self] in self?.allow() },
            onHover: { [weak self] in self?.hoverChanged($0) }
        ))
        let screen = Self.screen(for: anchor)
        panel.setFrame(
            Self.frame(size: size, anchor: anchor, visibleFrame: screen?.visibleFrame),
            display: true
        )
        // The short hint has nothing to click; let clicks through to the app.
        panel.ignoresMouseEvents = hint == .pressCommandV

        let animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = animates ? 0 : 1
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        if animates {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Theme.Motion.hintFadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
        announce(hint)
        scheduleDismiss(after: hint == .allowPasting
            ? Theme.Motion.permissionHintDuration
            : Theme.Motion.copiedHintDuration)
    }

    /// Hides the hint now (the panel is opening again, say).
    func dismiss() {
        lifecycle?.cancel()
        lifecycle = nil
        panel?.orderOut(nil)
    }

    // MARK: Placement

    /// Where the hint goes: centered on where the panel was, just above its
    /// bottom edge; with no panel, centered near the bottom of the screen.
    /// Always inside `visibleFrame`.
    static func frame(size: CGSize, anchor: CGRect?, visibleFrame: CGRect?) -> CGRect {
        var origin: CGPoint
        if let anchor {
            origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.minY + Theme.Layout.hintPanelOffset)
        } else if let visibleFrame {
            origin = CGPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.minY + Theme.Layout.hintScreenOffset)
        } else {
            origin = .zero
        }
        if let visibleFrame {
            origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width)
            origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        }
        return CGRect(origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size)
    }

    /// The screen with the anchor's center, else the one under the mouse.
    private static func screen(for anchor: CGRect?) -> NSScreen? {
        let point = anchor.map { CGPoint(x: $0.midX, y: $0.midY) } ?? NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }

    // MARK: Lifecycle

    private func scheduleDismiss(after seconds: TimeInterval) {
        lifecycle?.cancel()
        lifecycle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.timeIsUp()
        }
    }

    private func timeIsUp() {
        if isHovering {
            isOverdue = true
        } else {
            fadeOut()
        }
    }

    private func hoverChanged(_ hovering: Bool) {
        isHovering = hovering
        if !hovering, isOverdue {
            isOverdue = false
            scheduleDismiss(after: Theme.Motion.copiedHintDuration)
        }
    }

    private func fadeOut() {
        guard let panel, panel.isVisible else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            dismiss()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.Motion.hintFadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }
        lifecycle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Theme.Motion.hintFadeDuration))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func allow() {
        dismiss()
        openSettings()
    }

    /// VoiceOver reads the hint, which never takes focus.
    private func announce(_ hint: PastePlan.Hint) {
        var message = PasteHintCopy.spokenTitle
        if hint == .allowPasting {
            message += " " + PasteHintCopy.permissionDetail(osMajorVersion: osMajorVersion)
        }
        VoiceOver.announce(message)
    }
}
