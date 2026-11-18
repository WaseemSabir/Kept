/// The composition root: creates Kept's long-lived objects once and wires
/// them together. Nothing else creates controllers or reaches for singletons.
@MainActor
final class AppEnvironment {
    let panelController: PanelController
    private let statusItemController: StatusItemController
    private let hotkeyController: HotkeyController

    init() {
        let panelController = PanelController()
        self.panelController = panelController
        statusItemController = StatusItemController(togglePanel: { [panelController] in panelController.toggle() })
        hotkeyController = HotkeyController()
    }

    /// Starts listening for Kept's global shortcuts.
    func start() {
        hotkeyController.start(togglePanel: { [panelController] in panelController.toggle() })
    }
}
