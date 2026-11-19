import SwiftUI

/// Kept's icon, name and version, what it is, its license and project page,
/// the way back to the welcome window, and a quiet note if the history had
/// trouble at launch.
struct AboutPane: View {
    let model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: model.appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: Theme.SettingsLayout.aboutIconSize, height: Theme.SettingsLayout.aboutIconSize)
                .accessibilityHidden(true)
            Text("Kept")
                .font(Theme.SettingsLayout.aboutName)
                .padding(.top, 8)
            Text(model.about.versionLine)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)
            Text("A clipboard history for your Mac.")
                .padding(.top, 14)
            if let url = AboutInfo.projectURL {
                Link("github.com/WaseemSabir/Kept", destination: url)
                    .padding(.top, 4)
            }
            Text("Free and open source under the MIT License.")
                .font(Theme.SettingsLayout.note)
                .foregroundStyle(.secondary)
                .padding(.top, 14)
            Button("Show welcome window") { model.onShowWelcome() }
                .controlSize(.small)
                .padding(.top, 14)
            if let note = model.historyHealthNote {
                Text(note)
                    .font(Theme.SettingsLayout.note)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: Theme.SettingsLayout.contentWidth)
                    .padding(.top, 10)
            }
        }
        .padding(.vertical, 28)
        .frame(width: Theme.SettingsLayout.width)
    }
}
