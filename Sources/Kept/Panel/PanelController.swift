import AppKit
import KeptCore
import SwiftUI

/// Owns the floating panel: builds its content, places it, shows or hides it
/// without activating Kept, and routes its key presses to the view model.
@MainActor
final class PanelController {
    private let panel: FloatingPanel
    private let model: PanelViewModel
    /// Where the panel opens when nothing says otherwise (the setting).
    private let position: @MainActor () -> PanelPosition
    /// Called just before the panel shows (to put away a copy-only hint).
    var willShow: (@MainActor () -> Void)?
    /// The menu bar icon's frame on screen, or `nil` while it isn't showing.
    var statusItemFrame: @MainActor () -> CGRect? = { nil }

    init(
        model: PanelViewModel,
        resources: PanelResources,
        position: @escaping @MainActor () -> PanelPosition = { .activeScreenCenter }
    ) {
        self.model = model
        self.position = position
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: Theme.Layout.panelSize))
        panel.contentView = Self.makeContentView(model: model, resources: resources)
        panel.onResignKey = { [weak self] in self?.hide() }
        panel.keyHandler = { [weak self] press in self?.handle(press) ?? false }
        model.onDismiss = { [weak self] in self?.hide() }
        model.hintAnchor = { [weak self] in self?.panel.frame }
        model.pageSize = Self.visibleRowCount - 1
    }

    var isVisible: Bool { panel.isVisible }

    /// Shows the panel, or hides it if it's showing.
    /// - Parameter position: where to open it; `nil` for the setting.
    func toggle(at position: PanelPosition? = nil) {
        if isVisible {
            hide()
        } else {
            show(at: position)
        }
    }

    /// Resets the panel (empty search, first clip), places it and makes it
    /// key. `orderFrontRegardless` + `makeKey` (rather than activating Kept)
    /// keeps the user's app frontmost.
    /// - Parameter position: where to open it; `nil` for the setting.
    func show(at position: PanelPosition? = nil) {
        willShow?()
        model.prepareForShow()
        place(at: position ?? self.position())

        let animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = animates ? 0 : 1
        panel.orderFrontRegardless()
        panel.makeKey()
        guard animates else { return }
        let panel = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.Motion.panelAppearDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    /// Opens the panel with the inline "clear unpinned clips?" confirmation,
    /// for "Clear history…" in the menu bar menu: no alert, so the app the
    /// user is working in stays active.
    func showClearConfirmation(at position: PanelPosition? = nil) {
        show(at: position)
        model.perform(.requestClearUnpinned)
    }

    // MARK: Keys

    /// Turns a key press into a command. Returns `false` to let the key reach
    /// the search field (typing, ⌫, ←/→).
    private func handle(_ press: KeyPress) -> Bool {
        guard let command = PanelKeyRouter.command(for: press) else { return false }
        if case .edit(let action) = command {
            return sendEditAction(action)
        }
        return model.perform(command)
    }

    /// Kept is an agent app without an Edit menu, so ⌘X/⌘C/⌘V/⌘A/⌘Z have no
    /// menu item to trigger them; the panel sends their actions to the search
    /// field itself.
    private func sendEditAction(_ action: TextEditAction) -> Bool {
        let selector: Selector = switch action {
        case .cut: #selector(NSText.cut(_:))
        case .copy: #selector(NSText.copy(_:))
        case .paste: #selector(NSText.paste(_:))
        case .selectAll: #selector(NSText.selectAll(_:))
        case .undo: Selector(("undo:"))
        case .redo: Selector(("redo:"))
        }
        guard let responder = panel.firstResponder else { return false }
        return responder.tryToPerform(selector, with: nil)
    }

    // MARK: Placement

    /// Rows that fit between the search bar and the footer.
    private static var visibleRowCount: Int {
        let listHeight = Theme.Layout.panelSize.height - Theme.Layout.searchBarHeight - Theme.Layout.footerHeight
        return max(1, Int(listHeight / Theme.Layout.rowHeight))
    }

    /// Moves the panel to `position` (see `PanelPlacement`): the center of
    /// the screen under the pointer, at the pointer, or below the menu bar
    /// icon, always inside the screen's visible frame.
    private func place(at position: PanelPosition) {
        let screens = NSScreen.screens.map {
            PanelPlacement.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        guard let frame = PanelPlacement.frame(
            for: position,
            size: panel.frame.size,
            screens: screens,
            mouse: NSEvent.mouseLocation,
            statusItem: statusItemFrame()
        ) else {
            panel.center()
            return
        }
        panel.setFrameOrigin(frame.origin)
    }

    // MARK: Content

    /// SwiftUI content on a vibrancy background that fills the whole panel,
    /// including the hidden title bar area. With Reduce Transparency on, the
    /// system draws the material opaque.
    private static func makeContentView(model: PanelViewModel, resources: PanelResources) -> NSView {
        let background = NSVisualEffectView()
        background.material = Theme.Layout.panelMaterial
        background.blendingMode = .behindWindow
        background.state = .active

        let hostingView = NSHostingView(rootView: PanelView(model: model, resources: resources).ignoresSafeArea())
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: background.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        return background
    }
}
