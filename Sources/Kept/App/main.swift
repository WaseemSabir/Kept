import AppKit

// Kept is an agent app: no Dock icon and no main menu, only the menu bar item,
// the global shortcut and the panel. `LSUIElement` in Info.plist does this for
// the bundled app; setting the policy here also covers running the bare binary.
//
// Top-level code runs on the main thread; `assumeIsolated` states that for the
// main-actor AppKit setup below.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)

    // NSApplication holds its delegate weakly; keep ours alive while it runs.
    withExtendedLifetime(delegate) {
        application.run()
    }
}
