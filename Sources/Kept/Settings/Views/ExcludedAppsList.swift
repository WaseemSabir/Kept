import SwiftUI

/// The apps Kept never captures from: icon and name per row, with add,
/// remove and restore-defaults buttons below, like lists in System Settings.
struct ExcludedAppsList: View {
    let model: SettingsModel
    @State private var selection = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.SettingsLayout.controlSpacing) {
            list
            HStack(spacing: 2) {
                Button {
                    Task { await model.chooseAppsToExclude() }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 18)
                }
                .help("Add apps")
                .accessibilityLabel("Add apps")
                Button {
                    removeSelection()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 20, height: 18)
                }
                .disabled(selection.isEmpty)
                .help("Remove the selected apps")
                .accessibilityLabel("Remove the selected apps")
                Spacer(minLength: 0)
                Button("Restore defaults") {
                    selection.removeAll()
                    model.restoreDefaultExcludedApps()
                }
                .disabled(!model.canRestoreDefaultExcludedApps)
            }
            .buttonStyle(.borderless)
        }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(model.excludedApps) { app in
                HStack(spacing: 8) {
                    Image(nsImage: model.icon(for: app))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: Theme.SettingsLayout.excludedAppIconSize, height: Theme.SettingsLayout.excludedAppIconSize)
                        .accessibilityHidden(true)
                    Text(app.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(app.isInstalled ? Color.primary : Color.secondary)
                    if !app.isInstalled {
                        Spacer(minLength: 4)
                        Text("Not installed")
                            .font(Theme.SettingsLayout.note)
                            .foregroundStyle(.tertiary)
                    }
                }
                .help(app.bundleID)
                .tag(app.bundleID)
            }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: Theme.SettingsLayout.excludedAppsHeight)
        // The label beside the list lines up with its first row.
        .alignmentGuide(.firstTextBaseline) { $0[.top] + 17 }
        .onDeleteCommand(perform: removeSelection)
        .accessibilityLabel("Excluded apps")
    }

    private func removeSelection() {
        model.removeExcludedApps(selection)
        selection.removeAll()
    }
}
