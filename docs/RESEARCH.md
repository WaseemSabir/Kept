# Kept — Research

Research for Kept, a lean, native, open-source clipboard manager for macOS. Done 2026-11-18,
when macOS 27 is current. **(unverified)** marks claims that rest on one secondary source or
that could not be confirmed. Maccy, Clipy and Flycut facts come from reading their source
code (cloned 2026-11-18), not from marketing pages.

## Summary

- **CopyClip 2** ($7.99, Mac App Store and direct) is a polished, **text-only** menu bar manager.
  It keeps up to 9,999 clips and has search, pins, ⌘1–⌘0 quick paste, direct paste, a plain-text
  mode, excluded apps, concealed-type skipping, themes and Quick Look. It has no images, no files,
  no sync and no multi-paste.
- **Table stakes in 2026:** a global hotkey opens a panel, you type to filter, and ⏎ pastes into
  the app you were using. Users also expect pins, plain-text paste, text + images + files,
  password-safe defaults, pause capture, and launch at login.
- **macOS 26 ships its own clipboard history** in Spotlight (⌘Space, then ⌘4; 30 min / 8 h / 7 d
  retention, no pins). Kept has to beat it on speed, keyboard flow, pins and privacy controls.
- **Kept's position:** as light as Maccy, as polished as CopyClip, plus images and files. No sync,
  AI, text transforms, pinboards or themes.
- **Architecture:** an `LSUIElement` agent app with an `NSStatusItem` and a non-activating
  `NSPanel` that hosts SwiftUI. It polls `changeCount` (0.5 s), uses the KeyboardShortcuts package
  (Carbon) for the hotkey, posts a `CGEvent` ⌘V to paste, stores data in SQLite plus blob files,
  and uses `SMAppService` for login.
- **Top risks:** (1) permissions churn. Paste needs a permission that ad-hoc signed builds lose on
  every update, and macOS 27.3 is restructuring that permission. (2) Apple's coming
  pasteboard-privacy alerts. (3) Homebrew's official cask repo now requires a notarized
  Developer ID build.
- **Recommendation:** target macOS 14+, ship Developer ID signed and notarized builds
  (about $99/yr), and turn on App Sandbox from day one.

## CopyClip 2 feature inventory

| Feature | Notes | Source |
|---|---|---|
| Menu bar app | Lives in the menu bar; listing also says "menu bar and Dock". No main window. | MAS, FIPLAB help *Getting Started* |
| History size | Up to **9,999** clips; oldest pruned. Default count **not confirmed**. Paged list (◀ 1 of 58 ▶). | MAS, help *Clipboard History* |
| Content types | **Text only**: plain, rich text, URLs, code. **No images, no files** (by design, "lightweight"). | help *Image Support* |
| Search | Real-time filter. Optional "Clear search on hide". Match mode (substring vs fuzzy) **not confirmed**. | help *Search* |
| Global hotkey | Default **⌃Space**, customizable. A second hotkey opens a compact pop-up menu at the cursor. Option to open the main window at the cursor (v3.990). | help *Keyboard Shortcuts*, product page, MAS notes |
| Quick paste | **⌘1–⌘9, ⌘0** for the first 10 clips. Panel must be open. | MAS, help |
| Keyboard nav | Arrow keys, and ⏎ pastes the selection (added v3.989). | product page, MAS notes |
| Direct paste | "Paste Directly" (Advanced). Needs Accessibility, renamed "Device Control and Data Access" on macOS 27. The MAS build needed a separate helper app until v3.990 (Mar 2026). Off → copy-only. | help *Direct Pasting* |
| Plain text | Global "Paste formatted text" toggle (off = everything pasted as plain text). No per-paste modifier **confirmed**. | help *Preferences* |
| Pins | Pinned section on top, never pruned, keeps its own order. Setting for whether new pins go to top or bottom. Pin shortcut **⇧⌘P**. | help *Pinned Clips*, MAS |
| Edit / rename | Edit clip text; custom title tags (v3.93). | help, MAS notes |
| Delete | Per clip (context menu), Delete All, "Delete All Clips Except Pinned" (v3.991). No undo. | help, MAS notes |
| Excluded apps | "Exceptions" list (+/−, app icons shown). | help *Preferences* |
| Sensitive data | Skips `org.nspasteboard.ConcealedType` (since v3.4, 2019). | MAS notes |
| Pause | "Private Mode": Start/Stop Recording from the menu; dimmed icon while paused. | product page, help *Stopped Recording* |
| Source info | Hover tooltip: source app, content type, paste count, full text. | MAS |
| Preview | **Space** = Quick Look-style preview. | product page |
| Multi-select | ⌘-click multi-select (v3.988), but **no multi-paste or paste stack**. | MAS notes, help *Paste Multiple* |
| Appearance | 10 themes, resizable window, height adapts to the screen. | MAS |
| Login / startup | Start at Login, Hide window at startup. | help *Preferences* |
| iCloud / sync | **Not found** in any source. Assume none. | — |
| Snippets / pinboards | None beyond pins with custom titles. | — |
| Requirements | macOS 12+ (listing and site; some release notes conflict), 4.1 MB, English only. | MAS, fiplab.com |

FIPLAB's docs say Accessibility is needed to *monitor* the clipboard. That is not technically
true: reading `NSPasteboard` needs no permission, and only synthesizing ⌘V does.

## Landscape

| App | Price / license | Types | Signature UX | Notes |
|---|---|---|---|---|
| **Maccy** | Free, MIT. Paid on MAS (~$10) to fund development | Text, RTF, HTML, images, files | ⇧⌘C panel. Type to search (exact / fuzzy / regex / mixed). Pins get letter shortcuts. Preview. OCR on images. | macOS 14+. SwiftData. Default 200 items. Many settings exist only as `defaults write` keys. |
| **Clipy** | Free, MIT | Text, rich, images, files | `NSMenu`-based. ⇧⌘V main menu, ⌃⌘V history, ⇧⌘B snippets (folders) | macOS 14+, actively maintained (commit 2026-11-18). |
| **Flycut** | Free, MIT (+ MAS, iOS) | **Plain text only** | ⇧⌘V "bezel" HUD: step through history with arrows, ⏎ to paste. Favorites store. | Dev-focused. Fixed macOS 27 menu-bar clicks in Aug 2026. |
| **PastePal** | Free; Pro $14.99 one-time | Text, images, files | Edge panel, collections, 75+ text transforms | Optional iCloud sync, iOS apps. macOS 14+. |
| **Paste** | $3.99/mo, $29.99/yr (lifetime listed) | All | Bottom-of-screen card strip. ⇧⌘V; ⏎ paste; ⇧⏎ plain; ⌘1–9; Paste Stack ⇧⌘C | iCloud sync, shared pinboards. Polished but subscription. |
| **Raycast** | Free; Pro for >3-month retention | Text, images, files, links, colors | Launcher command. ⏎ paste, ⌘⏎ copy, ⌘. pin, ⌘X delete, ⌘P type filter | OCR, "prefer plain text" setting, encrypted local store, password managers ignored by default. |
| **Alfred** | Powerpack (paid) | Text, images, file links | Launcher viewer. ⏎ pastes. "clear" deletes the last 5 min / 15 min / all | Off by default for privacy. Retention 24 h–3 mo. Concealed data ignored by default. |
| **macOS 26 Spotlight** | Built in | Text, images (per reports) | ⌘Space then ⌘4 | Retention 30 min / 8 h / 7 d (26.1), no pins **(secondary sources)**. |

**What users love:** hotkey → type a few letters → ⏎, without touching the mouse; native, light
and free or one-time priced (Maccy, PastePal); direct paste and ⌘1–9; pins for recurring
snippets; images and files kept alongside text; password managers excluded out of the box.

**Common complaints (avoid these):**
- Subscriptions (Paste).
- "Paste doesn't work." Both the CopyClip and Maccy FAQs open with the Accessibility permission,
  and users must re-grant it after updates.
- Text-only history (CopyClip, Flycut).
- Passwords leaking when an app doesn't set ConcealedType. Example: 1Password's Safari extension.
- Freezes on huge clips. Maccy #845: 55 MB of text froze search. CopyClip warns about memory use
  with thousands of clips.
- Hotkey clashes. ⌃Space is macOS's input-source switch. ⇧⌘C opens Chrome DevTools.
  Option-only hotkeys break in some contexts.
- The menu bar icon vanishing on macOS 26 because of the "Allow in the Menu Bar" setting.
- Power settings hidden behind `defaults write`.

## Recommended Kept feature set

### P0: MVP (must ship)
1. **Menu bar agent** (`LSUIElement`). The status item click toggles the panel, and right-click opens Pause / Settings / Quit. *(Every competitor works this way.)*
2. **Capture text (plain + RTF/HTML), images and file URLs**, with dedup (re-copying moves the item to the top). *(CopyClip's biggest gap. Everyone else has it.)*
3. **Floating keyboard panel**, opened by global hotkey: search field focused, list, live filtering. *(The core job.)*
4. **Paste into the previous app** on ⏎ via synthesized ⌘V. If the permission is missing, copy instead and show a hint. *(The defining interaction. It must degrade gracefully.)*
5. **Plain-text paste** per action (⌥⏎), plus a global "always paste plain text" setting. *(CopyClip, Paste and Raycast all have it.)*
6. **Quick paste ⌘1–⌘9** on the visible rows. *(Muscle memory from CopyClip and Paste.)*
7. **Pins**: pinned section on top, never pruned, manual order. *(Replaces "snippets" with zero extra concepts.)*
8. **Delete item / clear history (keeps pins)**. *(Basic hygiene.)*
9. **Privacy defaults**: honor nspasteboard.org markers, a default excluded-apps list, pause capture and "ignore next copy". *(Trust is table stakes.)*
10. **Source app icon and age per row.** *(Cheap, and helps you scan.)*
11. **Settings**: hotkey recorder, launch at login, history size, paste vs copy-only, plain-text default, excluded apps. *(Keep it to one small window.)*
12. **Persistence across restarts** with a size limit (default 500 unpinned items) and image caps. *(Bounded resource use.)*
13. **Permission onboarding**: explain Accessibility (or Device Control) access when the user first pastes, not at launch. *(The top support issue for competitors.)*

### P1: should ship soon
- **Preview pane** (⌘Y) for long text, images and files, with facts (source, time, size). *(CopyClip and Maccy have it. DESIGN.md already lays it out.)*
- **Type filter** (All / Text / Images / Files / Links) and fuzzy matching. *(Raycast's ⌘P filter is loved.)*
- **Edit text / rename (title) a clip**, mainly for pins. *(CopyClip has it, and it makes pins into snippets.)*
- **Panel position setting**: center of active screen (default), at the mouse, under the menu bar icon. *(Maccy and CopyClip offer it.)*
- **Global "paste clipboard as plain text" hotkey** (no default). *(FIPLAB sells this as a separate app.)*
- **Universal Clipboard toggle** (`com.apple.is-remote-clipboard`) and age-based expiry / clear on quit. *(Privacy knobs that cost little.)*
- **Auto-update** (Sparkle 2) for direct downloads. *(Homebrew users update through brew.)*
- **VoiceOver labels and Reduce Motion / Transparency support.** *(Native-quality bar.)*

### P2: later / maybe
- OCR text in images for search (Vision `VNRecognizeTextRequest`; Maccy and Raycast have it).
- Multi-select → paste joined, or paste stack (sequential paste).
- Ignore by regex (Maccy), "ignore all apps except" mode.
- App Intents / Shortcuts actions (Maccy ships some).
- Color swatches for hex strings, link favicons.
- Optional encryption at rest (Raycast does it; Kept relies on FileVault plus 0600 file permissions until then).
- Localization.

### Out of scope (bloat)
iCloud or any sync; iOS app; AI features; text transforms; pinboards, collections and shared
boards; themes beyond system light/dark; snippet *expansion* (TextExpander territory); scripting or
plugins; browser extensions; analytics and telemetry; Dock-icon UI; a Mac App Store-first build.

## Keyboard shortcut map

**Global** (set with the recorder; only the first has a default):

| Action | Default | Rationale |
|---|---|---|
| Open / close Kept | **⇧⌘V** | Same as Flycut, Clipy and Paste. Caveat: it shadows "paste and match style" in Chrome, Google Docs and Slack, and VS Code's Markdown preview. Document ⌃⌘V as the alternative. |
| Paste clipboard as plain text (P1) | none | ⌥⇧⌘V is the system "Paste and Match Style". Don't take it. |
| Pause / resume capture | none | Also in the menu and on ⌥-click of the status item (Maccy and Flycut convention). |

Avoid Option-only or Shift-only combinations and keys that type a character (⌥C → ç). They fail
on macOS 15.0–15.1 (sandboxed apps) and in secure input fields. Require ⌘ or ⌃.

**In panel** (the search field always has focus, so plain letters type):

| Key | Action | Prior art |
|---|---|---|
| type | Filter | All |
| ↑ / ↓, ⌃P / ⌃N | Move selection | Maccy (also ⌃J/⌃K) |
| ⌘↑ / ⌘↓, Home / End, PgUp / PgDn | First / last / page | Maccy, Paste, Flycut |
| ⏎ | Paste selected into the previous app | CopyClip, Paste, Raycast, Alfred |
| ⌥⏎ | Paste as plain text | Maccy uses ⌥⇧⏎, Paste uses ⇧⏎. ⌥ echoes "Match Style" |
| ⌘⏎ | Copy only (no paste) | Raycast |
| ⌘1–⌘9 | Paste row N | CopyClip, Paste |
| ⌥⌘1–⌥⌘9 | Paste row N as plain text | Paste uses ⇧⌘1–9 |
| ⌘P | Pin / unpin | CopyClip ⇧⌘P, Raycast ⌘., Maccy ⌥P |
| ⌥⌘↑ / ⌥⌘↓ | Move the selected pin up / down (drag works too) | Finder/Xcode ⌥⌘ arrows move items |
| ⌘⌫ | Delete selected item | Finder "Move to Trash". Plain ⌫ edits the search, so it can only mean "delete item" when search is empty. **DESIGN.md's footer shows ⌫: reconcile.** |
| ⌥⌘⌫ | Clear unpinned history (confirm) | Maccy |
| ⌘Y | Preview (P1) | Finder Quick Look, Raycast. Space can't be used because it types. |
| ⌘E / ⌘R | Edit / rename (P1) | Paste |
| ⌃U | Clear search | Maccy, Emacs |
| Esc | Clear search if non-empty, else close | Common |
| ⌘, | Settings | macOS |

## Technical notes

**Minimum OS: macOS 14.** Maccy, Clipy and PastePal all require 14. It gives you Observation,
SwiftUI `onKeyPress`, `SettingsLink`, cooperative activation and `SMAppService`. Test on 14, 15, 26
and 27. macOS 26 is the last release for Intel, so ship a universal binary.

### 1. Clipboard monitoring
- macOS has **no pasteboard-change notification**. Poll `NSPasteboard.general.changeCount` with a
  main-run-loop `Timer`. Maccy defaults to **0.5 s** (`clipboardCheckInterval`). Set
  `timer.tolerance` to about 0.1–0.2 s so wake-ups can be coalesced, and read contents only when
  the count changes. Maccy also offers ignore-only-next-copy and pause flags.
- On a change, check `pasteboard.types` against the ignore rules **before** reading any data. That
  is cheaper, and it matters for pasteboard privacy (§12). Maccy notes that `NSPasteboard.types`
  returns the union of all items' types.
- Iterate `pasteboardItems` and merge them into **one** record. BBEdit and Edge write two items,
  and Finder writes one item per file. Skip whitespace-only strings unless the RTF/HTML has text.
- Capture `.string`, `.rtf`, `.html`, `.png`, `.tiff`, `public.jpeg`, `public.heic` and `.fileURL`.
  Skip `dyn.*`, `com.microsoft.ole.source.*`, `com.apple.webarchive` / "Apple Web Archive pasteboard
  type" (tens of MB), and Chromium/WebKit custom data (`org.chromium.web-custom-data`,
  `com.apple.WebKit.custom-pasteboard-data`). Maccy's lists are a good template.
- **Primary kind** (heuristic, verify with Pasteboard-Viewer):
  - `fileURL` → File(s).
  - Image types and no non-empty string → Image.
  - Otherwise → Text, keeping RTF/HTML for formatted paste.
  - Office and Numbers add image or PDF renderings next to text, so prefer text when a string exists.
- Store every captured representation so re-paste is faithful. Display only the primary one.
- Dedup on a SHA-256 of the primary payload, then bump `lastCopiedAt` / `copyCount`.
- Cap title and search text. Maccy cuts titles to 1,000 chars and fuzzy search to 5,000. Maccy also
  sanitizes titles because some Unicode scalars **hang CoreText on macOS 26** (Maccy #1520).
- **Writing back:** `clearContents()`, then `setData(_:forType:)` for each type. For multiple files,
  use `writeObjects([NSPasteboardItem])` (Maccy found per-type writes break multi-file paste).

### 2. Privacy markers (nspasteboard.org)
- Never record content when any of these is present: `org.nspasteboard.ConcealedType` (secret;
  hide it or encrypt it), `org.nspasteboard.TransientType` (must not appear in history), or
  `org.nspasteboard.AutoGeneratedType` (no user intent). Maccy hard-codes all three.
- Ignore these legacy types by default too (Maccy's removable defaults): `com.agilebits.onepassword`
  (treat as concealed), `de.petermaurer.TransientPasteboardType`, `com.typeit4me.clipping`,
  `Pasteboard generator type`, `net.antelle.keeweb`.
- `org.nspasteboard.source` holds the origin's bundle ID (may be ""). Prefer it over the frontmost
  app. `com.apple.is-remote-clipboard` marks Universal Clipboard content (P1 toggle).
- When Kept writes: set `org.nspasteboard.source` to the item's original app (as Maccy does), plus a
  private marker type such as `<bundle-id>.own`.
- Markers aren't universal. 1Password's Safari extension reportedly omits them. So also ship
  default excluded apps: Passwords, Keychain Access, 1Password, Bitwarden, KeePassXC. **Verify the
  bundle IDs** (e.g. `com.apple.Passwords`, `com.apple.keychainaccess`,
  `com.1password.1password`) before shipping. Alfred and Raycast exclude password apps by default.

### 3. Source app
`NSWorkspace.shared.frontmostApplication` at detection time gives `.bundleIdentifier`,
`.localizedName` and `.icon`. It can be wrong by up to one poll interval if the user switches apps;
that's acceptable. Store only the bundle ID. Resolve icons lazily with
`NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` and `icon(forFile:)`, and cache them
per bundle ID (Maccy's `ApplicationImageCache`). Excluded-app checks use the same bundle ID.

### 4. Global hotkeys
- **Carbon `RegisterEventHotKey` + `InstallEventHandler`** (`kEventHotKeyPressed/Released`) is still
  the only way to get global hotkeys with no permission prompt. It works in the sandbox.
- Alternatives: `NSEvent.addGlobalMonitorForEvents` needs Accessibility and can't swallow the key.
  A `CGEvent.tapCreate` tap needs Input Monitoring. Both are overkill.
- **sindresorhus/KeyboardShortcuts** (Maccy uses it; MIT) wraps `RegisterEventHotKey` and provides:
  - `KeyboardShortcuts.Recorder` (SwiftUI) and `RecorderCocoa` (AppKit).
  - Storage in UserDefaults.
  - Warnings about conflicts with system and menu shortcuts.
  - `onKeyUp` / `onKeyDown` and an async `events(for:)`.
  - Mac App Store compatibility.

  Its current `Package.swift` needs **swift-tools 6.2** (Xcode 26 toolchain). Its README advises
  against shipping default shortcuts; we ship exactly one.
- **soffes/HotKey** is a thinner Carbon wrapper with no recorder.
- Rolling your own recorder means:
  - A focused view that captures `keyDown` and requires ⌘ or ⌃.
  - Showing key names with the current layout (`TISCopyCurrentKeyboardLayoutInputSource` +
    `UCKeyTranslate`).
  - Detecting clashes when `RegisterEventHotKey` fails.

  That's about 300 lines. **Recommend the package.**
- **Gotchas:**
  - macOS 15.0 rejected Option-only and Option+Shift-only hotkeys for sandboxed apps
    (−9868 reported). Apple relaxed this in 15.2. Reports of intermittent failures persist.
  - Combinations that type a character fail in secure input (Maccy docs).
- **In-panel keys:** SwiftUI `.onKeyPress` (14+) or `NSEvent.addLocalMonitorForEvents(matching:
  .keyDown)` on the panel. Match keys layout-aware. Maccy uses the `Sauce` package and special-cases
  "Dvorak – QWERTY ⌘" layouts.

### 5. Pasting into the previous app
- **Flow:** the panel never activates Kept, so the target app stays frontmost. Close the panel,
  write the item to the pasteboard, then post ⌘V. Maccy and Clipy work this way:
  ```swift
  let src = CGEventSource(stateID: .combinedSessionState)
  src?.setLocalEventsFilterDuringSuppressionState([.permitLocalMouseEvents, .permitSystemDefinedEvents],
                                                  state: .eventSuppressionStateSuppressionInterval)
  let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
  let up   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
  down?.flags = flags; up?.flags = flags        // Maccy: .maskCommand | 0x000008 (left-⌘ device bit, Flycut PR #18)
  down?.post(tap: .cgSessionEventTap); up?.post(tap: .cgSessionEventTap)   // Clipy: .cgAnnotatedSessionEventTap
  ```
- **Key code:** `kVK_ANSI_V` (9) is a *physical* key. On Dvorak and similar layouts, find the key
  that produces "v" (Sauce, or `UCKeyTranslate`). Some layouts switch to QWERTY while ⌘ is held.
- **Permission:** posting events needs TCC's *PostEvent* privilege, which System Settings lists under
  Accessibility.
  - Check it with `CGPreflightPostEventAccess()` and request it with `CGRequestPostEventAccess()`
    (both macOS 10.15+).
  - Maccy and Clipy use `AXIsProcessTrustedWithOptions`, which checks full Accessibility. Apple DTS
    (2026) says AX-gated APIs are incompatible with the sandbox, but PostEvent and ListenEvent are
    compatible.
  - If permission is missing, fall back to copy-only plus a "Press ⌘V" hint.
- **macOS 27 churn:**
  - The pane is renamed **"Device Control and Data Access"** (FIPLAB and Microsoft docs).
  - 27.3 beta 2 (Apple, 2026-11-16) **splits it** into "System & App Protection Override" and
    "Accessibility". It adds per-app scoping, an "ask every time" option and an indicator.
  - **Which bucket PostEvent falls into is unconfirmed.** Keep onboarding copy version-aware.
    DESIGN.md's error string names Accessibility only.
- **Don't re-capture your own write:** record `pasteboard.changeCount` right after writing and skip
  that count in the poller, or detect the private marker. Either way, just bump the item's timestamp.
- **If Kept ever activates** (Settings, an editing sheet): re-activate the previous app with
  `NSRunningApplication.activate(from:options:)` (macOS 14 cooperative activation;
  `activate(ignoringOtherApps:)` is deprecated). Wait for
  `NSWorkspace.didActivateApplicationNotification` before posting ⌘V; fixed sleeps are flaky.
- Untested edge cases: Terminal "Secure Keyboard Entry", password fields, Remote Desktop. Maccy has
  a focus-toggle hack for Chrome Remote Desktop and NetBeans.

### 6. Floating panel
- Maccy's `FloatingPanel` setup (Cindori's guide is similar):
  ```swift
  NSPanel(contentRect:, styleMask: [.nonactivatingPanel, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
  isFloatingPanel = true; level = .statusBar              // Cindori uses .floating
  collectionBehavior = [.auxiliary, .stationary, .moveToActiveSpace, .fullScreenAuxiliary]
  hidesOnDeactivate = false; animationBehavior = .none
  titleVisibility = .hidden; titlebarAppearsTransparent = true   // hide traffic lights
  override var canBecomeKey: Bool { true }                // lets the search field take keys
  ```
- Show it with `orderFrontRegardless(); makeKey()`, **not** `NSApp.activate`. The panel becomes key
  while the other app stays active, and `frontmostApplication` doesn't change. Close it in a
  `resignKey()` override (an outside click). Leave `becomesKeyOnlyIfNeeded = false` (the default)
  so typing works at once.
- Host SwiftUI with `NSHostingView` and focus search with `@FocusState`. Use `ScrollViewReader` and
  lightweight rows so thousands of items stay smooth.
- **Placement:**
  - The screen under `NSEvent.mouseLocation`, clamped to its `visibleFrame`.
  - Or centered on that screen.
  - Maccy also offers status item, window center and last position.
  - Placing at the text caret needs AX (`kAXFocusedUIElementAttribute`), which isn't sandbox-safe.
    Skip it.
- Raycast and Paste are closed source, so their exact technique is **not verified**.

### 7. Menu bar
- Use **`NSStatusItem`**: `NSStatusBar.system.statusItem(withLength: .variableLength)`, a template
  image, and `button.sendAction(on: [.leftMouseUp, .rightMouseUp])` to split left- and right-click.
  For right-click, temporarily assign `statusItem.menu` and call `button.performClick`. Set
  `behavior = .removalAllowed`.
- On macOS 27, replaying the original mouse event to open the menu stopped working (Flycut #326).
- **`MenuBarExtra`** (13+) has no API to open or close it programmatically or to reach its
  `NSStatusItem` or window. The `.menu` style blocks the run loop. That rules it out for a
  hotkey-driven panel without MenuBarExtraAccess, so skip it.
- Set `LSUIElement = YES` in Info.plist (no Dock icon). In agent apps the Settings window opens behind
  other windows. The `showSettingsWindow:` selector is dead on 14+; use `SettingsLink` /
  `openSettings` plus `NSApp.activate()`, or simply own an `NSWindow`.
- On macOS 26, **System Settings › Menu Bar › "Allow in the Menu Bar"** can hide the icon, and no API
  detects it. Always keep other ways in: the hotkey, ⌘, inside the panel, and opening Settings on
  relaunch (`applicationShouldHandleReopen`). Clipy has an un-removable Settings hotkey for the
  same reason.

### 8. Launch at login
- Use `SMAppService.mainApp.register()` / `unregister()` (13+). Read `.status` every time:
  `.enabled`, `.requiresApproval`, `.notRegistered` or `.notFound`. Users can change it in
  System Settings › General › Login Items.
- On `.requiresApproval`, call `SMAppService.openSystemSettingsLoginItems()`.
- Registering posts a "Login Item Added" notification.
- Ad-hoc or unsigned builds have been reported to return `.notFound` **(unverified)**.
- LaunchAtLogin-Modern is about 30 lines around this API, so inline it.

### 9. Sandboxing and distribution channel
- **Maccy ships with App Sandbox on** in both its GitHub and Mac App Store builds (one entitlements
  file: `app-sandbox`, `files.user-selected.read-only`, Sparkle `mach-lookup` exceptions). It still
  pastes with `CGEvent.post`. So the sandbox does **not** block synthesized paste once the user has
  granted access, which matches DTS.
- **Mac App Store:** App Review rejected a clipboard manager under Guideline 2.4.5 for `CGEvent.post`
  (Apple forum thread, Mar 2026, unresolved). Yet Maccy, Flycut and CopyClip 2 all ship there, and
  CopyClip used a helper app until 2026. Treat the store as a risk, not a v1 channel.
- **Recommendation:** direct distribution, sandbox **on**.
  - Nothing in P0 needs file access. File items store URLs, and re-pasting a URL needs no read
    access.
  - The sandbox costs us caret placement (skipped anyway) and adds Sparkle XPC setup (P1).

### 10. Persistence
- **Maccy:** SwiftData at `~/Library/Application Support/Maccy/Storage.sqlite`. `HistoryItem`
  (application, first/lastCopiedAt, numberOfCopies, pin, title) has a relationship to
  `HistoryItemContent` (type: String, value: Data). Image bytes are stored as blobs.
- It needed workarounds: a macOS 14 insert quirk, orphan cleanup and title sanitization. SwiftData
  is also widely reported to be slow with large or blob-heavy stores (Apple forums).
- **Options:**
  - SwiftData: least code, opaque, slow with blobs.
  - **SQLite** (GRDB.swift, or `import SQLite3` with a thin wrapper): explicit schema, FTS5, WAL,
    predictable.
  - JSON index + blob files: fine for ≤1k items, but every change rewrites the file and there is
    no index.
- **Recommend SQLite plus content-addressed blob files:**
  - Metadata and text go in the DB.
  - Images and large RTF/HTML go in `Application Support/Kept/blobs/<sha256>.<ext>`.
  - Pre-render thumbnails with `CGImageSourceCreateThumbnailAtIndex`.
  - Keep the newest N summaries in memory so the panel opens instantly.
- **Limits:**
  - Default 500 unpinned items; pins are exempt. CopyClip allows up to 9,999, Maccy defaults to 200.
  - Re-encode TIFF to PNG (screenshot TIFFs are huge).
  - Skip single items over about 20 MB (configurable).
  - Prune when total blob storage passes about 500 MB.
  - Index only the first ~5–10 KB of text.

### 11. Building the .app from SwiftPM, signing and notarization
- **Build:** `swift build -c release --arch arm64 --arch x86_64`. Find the binary with
  `--show-bin-path` rather than hard-coding the path.
- **Assemble** `Kept.app/Contents/{MacOS/Kept, Info.plist, Resources/AppIcon.icns}`. Info.plist
  needs `CFBundleIdentifier`, `CFBundleExecutable`, `CFBundlePackageType=APPL`,
  `CFBundleShortVersionString`, `CFBundleVersion`, `LSMinimumSystemVersion=14.0`,
  `LSUIElement=true` and `CFBundleIconFile`.
- Make the icon with `iconutil -c icns`. `.xcassets` and Icon Composer `.icon` files need Xcode's
  `actool`.
- **Avoid SwiftPM `resources:` / `Bundle.module`** in the app target. Its generated lookup can miss a
  hand-assembled `.app` and crash (Swift forums and project reports). Put files in
  `Contents/Resources` and use `Bundle.main`.
- **Sign inside-out** (nested frameworks such as Sparkle first; avoid `--deep` for signing):
  `codesign --force --options runtime --timestamp --entitlements Kept.entitlements -s "Developer ID Application: …" Kept.app`.
  For an ad-hoc signature use `-s -`. Check with `codesign --verify --strict -vv` and
  `spctl -a -vv`.
- **Notarize:**
  1. `ditto -c -k --keepParent Kept.app Kept.zip`
  2. `xcrun notarytool submit Kept.zip --keychain-profile <profile> --wait` (or `--key/--key-id/--issuer`
     in CI)
  3. `xcrun stapler staple Kept.app`, then zip or DMG it again.

  This needs the Apple Developer Program (about $99/yr).
- **Gatekeeper:** macOS 15 removed the Control-click "Open" bypass. Users of an unnotarized build
  must try to launch it, then use **System Settings › Privacy & Security › Open Anyway** (admin
  password).
- **Homebrew 5.0** (2025-11-12) deprecated casks that fail Gatekeeper, and they were removed from the
  official tap by **2026-09-01**. `--no-quarantine` is deprecated. So **homebrew/cask requires
  Developer ID + notarization**; otherwise ship a personal tap, and users still hit Gatekeeper.
- **TCC trap:** an ad-hoc signature's designated requirement is its cdhash, so **every new build
  silently loses the Accessibility grant**. The toggle still shows "on" (Clipy README; "tcc cdhash
  trap" post). Use Developer ID for releases. For local development, sign with one persistent
  self-signed certificate. Clean up with `tccutil reset Accessibility <bundle-id>`.
- **CI template:** Flycut's release workflow degrades gracefully. No secrets → ad-hoc; a certificate
  → signed; plus notary keys → notarized and stapled.
- Swift 6.2 back-deploy: a missing `libswiftCompatibilitySpan.dylib` has been reported. Test the
  built `.app` on macOS 14.

### 12. Pasteboard privacy (new risk)
- **What Apple added:** macOS 15.4 added `NSPasteboard.accessBehavior` (`.default`, `.ask`,
  `.alwaysAllow`, `.alwaysDeny`) and the `detect` APIs: `detectedPatterns(for:)`,
  `detectedValues(for:)` and `detectedMetadata(for:)`.
- **What it does:** a coming feature alerts the user when an app *programmatically* reads the
  general pasteboard without paste-related user input. Users manage it in Privacy & Security ›
  "Paste from Other Apps". Test it with
  `defaults write <bundle-id> EnablePasteboardPrivacyDeveloperPreview -bool yes`, and reset with
  `tccutil reset Pasteboard`.
- **Status:** whether it is enforced by default on macOS 26 or 27 is **not confirmed**. A commenter
  says the preview key was retired in 27.2 beta 2.
- **Why it matters:** a clipboard manager reads on every change, so it needs "Allow".
- **Plan:**
  - Check `accessBehavior` at launch and onboard the user if it isn't `.alwaysAllow`.
  - Apply ignore rules from `types` before reading data.
  - Never read contents at launch beyond `changeCount`.

## Sources

- CopyClip 2: https://apps.apple.com/us/app/copyclip-2-clipboard-manager/id1020812363?mt=12 · https://fiplab.com/apps/copyclip-for-mac
- CopyClip 2 help: `https://support.fiplab.com/copyclip-2/` + {getting-started, clipboard-history, search, pinned-clips, keyboard-shortcuts, direct-pasting, preferences, image-support, paste-multiple, stopped-recording, troubleshooting}
- Maccy README and source (`Clipboard.swift`, `FloatingPanel.swift`, `Storage.swift`, `Defaults.Keys+Names.swift`, `KeyChord.swift`, `Maccy.entitlements`, `docs/keyboard-shortcut-password-fields.md`): https://github.com/p0deje/Maccy · MAS: https://apps.apple.com/us/app/maccy/id1527619437 · #845: https://github.com/p0deje/maccy/issues/845
- Clipy (README, `PasteService.swift`): https://github.com/Clipy/Clipy · Flycut (`help.md`, release workflow): https://github.com/TermiT/Flycut
- PastePal: https://apps.apple.com/us/app/clipboard-manager-pastepal/id1503446680 · Paste: https://pasteapp.io/help/keyboard-shortcuts · https://apps.apple.com/app/paste-clipboard-manager/id967805235
- Raycast: https://manual.raycast.com/clipboard-history · https://raycast.com/core-features/clipboard-history · Alfred: https://www.alfredapp.com/help/features/clipboard/
- macOS 26 Spotlight clipboard: https://www.macrumors.com/2025/11/04/more-spotlight-clipboard-settings-macos-26-1/ · https://pasteapp.io/blog/macos-tahoe-clipboard-history (vendor)
- nspasteboard.org: http://nspasteboard.org/ · 1Password Safari report: https://www.1password.community/discussions/1password/safari-extension-doesnt-set-macos-pasteboard-type-like-desktop-app/45149/replies/168299
- KeyboardShortcuts: https://github.com/sindresorhus/KeyboardShortcuts · Option-key hotkeys on 15: https://developer.apple.com/forums/thread/763878 · https://blog.eternalstorms.at/?p=6658
- DTS on PostEvent / ListenEvent / Accessibility and Guideline 2.4.5: https://developer.apple.com/forums/thread/820594 · https://developer.apple.com/forums/thread/707680
- APIs: https://developer.apple.com/documentation/coregraphics/cgpreflightposteventaccess() · https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(from:options:) · https://developer.apple.com/documentation/servicemanagement/smappservice
- macOS 27.3 permission changes: https://developer.apple.com/news?id=oqng0zjk
- Pasteboard privacy: https://developer.apple.com/documentation/updates/appkit#macOS-pasteboard-privacy · https://developer.apple.com/documentation/AppKit/NSPasteboard/accessBehavior-86972 · https://mjtsai.com/blog/2025/05/12/pasteboard-privacy-preview-in-macos-15-4/
- Panel / menu bar: https://cindori.com/developer/floating-panel · https://github.com/orchetect/MenuBarExtraAccess · https://github.com/orchetect/SettingsAccess · https://developer.apple.com/forums/thread/788101
- Login items: https://github.com/sindresorhus/LaunchAtLogin/issues/100
- Distribution: https://workbrew.com/blog/what-homebrew-5-0-0-means-for-your-mac-fleet · https://www.macrumors.com/2024/08/06/macos-sequoia-gatekeeper-security-change/ · https://nickboy-github-io.pages.dev/posts/tcc-cdhash-trap/ · https://forums.swift.org/t/bundling-resources-with-a-swift-package-bundle-module-not-available/84185
