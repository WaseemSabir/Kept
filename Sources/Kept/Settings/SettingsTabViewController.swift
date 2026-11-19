import AppKit
import SwiftUI

/// Settings' panes as toolbar items, the standard look of a Mac settings
/// window: the window takes the selected pane's name and resizes to fit it,
/// keeping its top edge where it is.
@MainActor
final class SettingsTabViewController: NSTabViewController {
    /// Called when the user picks a pane.
    var onSelectPane: (@MainActor (SettingsPane) -> Void)?

    init(model: SettingsModel) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        // Swap panes at once; the window's resize is the only motion.
        transitionOptions = []
        for pane in SettingsPane.allCases {
            let controller = NSHostingController(rootView: SettingsPaneView(pane: pane, model: model))
            // The pane's height follows its content (a note appearing, say).
            controller.sizingOptions = [.preferredContentSize]
            controller.title = pane.title
            let item = NSTabViewItem(viewController: controller)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: nil)
            item.identifier = pane.rawValue
            addTabViewItem(item)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsTabViewController is created in code, not loaded from an archive.")
    }

    var selectedPane: SettingsPane {
        get {
            let panes = SettingsPane.allCases
            return panes.indices.contains(selectedTabViewItemIndex) ? panes[selectedTabViewItemIndex] : .general
        }
        set {
            guard let index = SettingsPane.allCases.firstIndex(of: newValue),
                  index != selectedTabViewItemIndex
            else { return }
            selectedTabViewItemIndex = index
        }
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindowToSelectedPane(animated: true)
        onSelectPane?(selectedPane)
    }

    override func preferredContentSizeDidChange(for viewController: NSViewController) {
        super.preferredContentSizeDidChange(for: viewController)
        guard viewController === selectedPaneController else { return }
        fitWindowToSelectedPane(animated: false)
    }

    private var selectedPaneController: NSViewController? {
        tabViewItems.indices.contains(selectedTabViewItemIndex)
            ? tabViewItems[selectedTabViewItemIndex].viewController
            : nil
    }

    /// Resizes the window to the selected pane's size, top edge fixed. Not
    /// animated under Reduce Motion or before the window is on screen.
    func fitWindowToSelectedPane(animated: Bool) {
        guard let window = view.window, let controller = selectedPaneController else { return }
        var size = controller.preferredContentSize
        if size.width <= 0 || size.height <= 0 {
            size = controller.view.fittingSize
        }
        guard size.width > 0, size.height > 0 else { return }

        let current = window.contentRect(forFrameRect: window.frame)
        guard current.size != size else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: current.origin, size: size))
        frame.origin.y = window.frame.maxY - frame.height
        let animates = animated && window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.setFrame(frame, display: true, animate: animates)
    }
}
