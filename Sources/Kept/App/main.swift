import AppKit

// Kept is an agent app: no Dock icon and no main menu, only the menu bar item,
// the global shortcut and the panel. `LSUIElement` in Info.plist does this for
// the bundled app; setting the policy here also covers running the bare binary.
//
// Top-level code runs on the main thread; `assumeIsolated` states that for the
// main-actor AppKit setup below.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)

    // `Kept --render-snapshots <dir>` draws the panel in sample states to PNG
    // files for design review, then quits. A developer tool, not a feature.
    if let directory = SnapshotRenderer.outputDirectory(from: CommandLine.arguments) {
        Task {
            let status = await SnapshotRenderer.run(writingTo: directory)
            exit(status)
        }
        application.run()
    } else {
        let delegate = AppDelegate()
        application.delegate = delegate

        // NSApplication holds its delegate weakly; keep ours alive while it runs.
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
