import SwiftUI

/// One pane at its natural height, pinned to the top of the window while the
/// window resizes to fit it.
struct SettingsPaneView: View {
    let pane: SettingsPane
    let model: SettingsModel

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        switch pane {
        case .general: GeneralPane(model: model)
        case .shortcuts: ShortcutsPane()
        case .privacy: PrivacyPane(model: model)
        case .about: AboutPane(model: model)
        }
    }
}
