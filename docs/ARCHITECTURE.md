# Kept — Architecture

Kept is a native macOS agent app (no Dock icon) written in Swift 6. It is
one Swift package with two layers:

- **`KeptCore`** — all the logic that does not need AppKit: models, capture
  policy, storage, search, preferences. Foundation-only, so it builds and is
  unit-tested on Linux as well as macOS.
- **`Kept`** — the macOS app: pasteboard I/O, hotkeys, the floating panel,
  the menu bar item, settings. AppKit + SwiftUI. Thin; it adapts the platform
  to `KeptCore` and renders state.

```
            ┌──────────────── Kept (macOS app) ────────────────┐
 NSPasteboard ─▶ PasteboardMonitor ─▶ PasteboardReader ──┐     │
            │                                            ▼     │
            │                    ┌──────── KeptCore ─────────┐ │
            │                    │ CapturePolicy → ClipBuilder│ │
            │                    │        ▼                   │ │
            │                    │   HistoryStore (SQLite +   │ │
            │                    │   BlobStore)  ──▶ ClipSearch│ │
            │                    │   Preferences              │ │
            │                    └────────────┬──────────────┘ │
            │                                 ▼                │
 ⇧⌘V ─▶ Hotkeys ─▶ PanelController ─▶ PanelViewModel ─▶ SwiftUI views
            │                                 │                │
            │                     PasteService (write + ⌘V) ◀──┘
            └──────────────────────────────────────────────────┘
```

## Package layout

```
Package.swift                 swift-tools 6.2; app targets only under #if os(macOS)
Sources/
  CSQLite/                    system library target (module.modulemap → sqlite3)
  KeptCore/
    Models/                   Clip, ClipKind, ClipRepresentation, SourceApp
    Capture/                  PasteboardType, PasteboardSnapshot, CapturePolicy, ClipBuilder
    Storage/                  SQLite (thin wrapper), Schema/migrations, BlobStore, HistoryStore
    Search/                   ClipSearch (matching, ranking, kind filter)
    Preferences/              Preferences (UserDefaults-backed, defaults in one place)
    Support/                  SHA256, small helpers (formatting, text sanitizing)
  Kept/                       macOS app (executable target)
    App/                      main.swift, AppDelegate, AppEnvironment (composition root)
    Clipboard/                PasteboardMonitor, PasteboardReader, PasteboardWriter, PasteService, KeyboardLayout
    Permissions/              PostEventPermission, PasteboardAccess
    Hotkeys/                  KeyboardShortcuts.Name definitions + handlers
    Panel/                    FloatingPanel (NSPanel), PanelController, PanelViewModel, Views/
    MenuBar/                  StatusItemController
    Settings/                 SettingsWindowController, Views/ (panes)
    DesignSystem/             Theme (tokens), Marker (highlighter), KeyCap, shared components
    Support/                  AppIconCache, ThumbnailCache
Tests/
  KeptCoreTests/              Swift Testing (`import Testing`); runs on Linux + macOS
  KeptTests/                  macOS-only tests for app-layer logic that can't live in core
Resources/                    Info.plist, Kept.entitlements, AppIcon assets (copied by the bundle script)
scripts/build-app.sh          assembles + signs Kept.app from `swift build` output
Makefile                      build / test / app / run / clean
.github/workflows/ci.yml      macOS: build, test, bundle · Linux: core tests
```

Resources are **not** SwiftPM `resources:`; the bundle script copies them into
`Kept.app/Contents/Resources` and code uses `Bundle.main`.

## Key types (KeptCore)

- `Clip` — one history entry: `id`, `kind`, `title` (display summary,
  sanitized, ≤1000 chars), `searchText` (≤10 KB), `contentHash` (SHA-256 of
  primary payload, dedup key), `sourceBundleID`, `firstCopiedAt`,
  `lastCopiedAt`, `copyCount`, `isPinned`, `pinOrder`, `byteSize`, plus
  kind-specific metadata (image pixel size, file count, color value).
- `ClipRepresentation` — one pasteboard type of a clip: `type` (UTI string)
  and either inline `Data` (small) or a blob reference (large).
- `ClipKind` — `.text`, `.richText`, `.link`, `.image`, `.file`, `.color`.
  Code-like text is `.text` with a `looksLikeCode` flag used only for
  rendering.
- `PasteboardSnapshot` — platform-neutral copy of what's on the pasteboard:
  ordered items of `(type, data)`, plus `changeCount` and source bundle ID.
  The app builds it from `NSPasteboard`; tests build it by hand.
- `CapturePolicy` — pure function from (types, source app, preferences) to
  `.record` / `.ignore(reason)`. Checked on **types before data is read**.
- `ClipBuilder` — snapshot → `ClipDraft` (kind detection, representation
  filtering, title/search text, hash).
- `HistoryStore` — `@MainActor`, `@Observable`. Owns the SQLite database and
  blob store; exposes the ordered list of clip summaries and mutations:
  `record(_:)`, `pin`, `unpin`, `movePin`, `delete`, `clearUnpinned`,
  `representations(for:)`, `prune()`.
- `ClipSearch` — pure: `(query, kind filter, clips) → ranked clips`.
  Case/diacritic-insensitive; all tokens must match; prefix/word-start/
  subsequence scoring; pinned first when the query is empty.
- `Preferences` — `@Observable` wrapper over `UserDefaults` with every
  default declared in one place.

## App layer

- **Composition root** — `AppEnvironment` creates the store, preferences,
  monitor, paste service and controllers once and injects them. No
  singletons beyond what AppKit forces.
- **PasteboardMonitor** — `Timer` on the main run loop every 0.5 s with
  0.15 s tolerance; compares `changeCount`; skips the change counts Kept
  wrote itself; asks `CapturePolicy` on types first; then reads data.
- **PanelController** — owns `FloatingPanel` (non-activating `NSPanel`,
  `.statusBar` level, `canBecomeKey = true`), shows it with
  `orderFrontRegardless(); makeKey()` so the target app stays frontmost,
  hides on `resignKey`.
- **PanelViewModel** — `@Observable`; holds query, filter, selection;
  derives visible clips via `ClipSearch`; turns key presses into intents.
- **PasteService** — writes the clip, hides the panel, posts ⌘V with
  `CGEvent` (layout-aware key code) if `CGPreflightPostEventAccess()`;
  otherwise copy-only plus a hint.
- **Hotkeys** — `KeyboardShortcuts` package (Carbon `RegisterEventHotKey`
  under the hood; no permission prompt; recorder UI for settings).

## Conventions

- Swift 6 language mode, strict concurrency. UI and stores are `@MainActor`.
- No force unwraps outside tests; errors are typed and surfaced, not
  swallowed.
- Each file has one primary type; folders mirror the layout above.
- Pure logic goes in `KeptCore` with tests. App-layer code stays thin.
- Minimum macOS 14. Sandboxed (`com.apple.security.app-sandbox`).
