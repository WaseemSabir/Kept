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
    Models/                   Clip, ClipKind, ClipFilter, ClipMetadata, PixelSize, ClipRepresentation, PasteboardItem, ClipDraft
    Capture/                  PasteboardType, PasteboardSnapshot, CaptureSettings, CapturePolicy (+ CaptureDecision),
                              ClipBuilder, ImageInspecting / PNGImageInspector, link / color / code detectors
    Storage/                  SQLite wrapper (Database, Statement, Value, Error), HistorySchema (migrations),
                              BlobStore, HistoryStore, HistoryLimits, HistoryStoreError
    Search/                   ClipSearch (matching, ranking, kind filter), SearchKey (folded text)
    Preferences/              Preferences (UserDefaults-backed), PreferenceDefaults (every default), PanelPosition
    Support/                  SHA256, TextSanitizer, RTF/HTML text extractors, KeptVersion
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

- `Clip` — one history entry, without its payload: `id` (UUID), `kind`,
  `title` (sanitized single line, ≤1,000 chars), `searchText` (sanitized,
  ≤8 KB), `contentHash` (SHA-256 of the primary payload, the dedup key),
  `sourceBundleID`, `firstCopiedAt`, `lastCopiedAt`, `copyCount`, `pinOrder`
  (`nil` = not pinned; `isPinned`), `byteSize`, and `metadata`
  (`ClipMetadata`: character count, `looksLikeCode`, link host, color hex,
  image pixel size and type, file count). Each clip caches its folded search
  text, so searching never re-normalizes.
- `ClipKind` — `.text`, `.richText`, `.link`, `.image`, `.file`, `.color`.
  Code-like text is `.text`/`.richText` with `metadata.looksLikeCode`, used
  only for rendering. `ClipFilter` — `all, pinned, text, links, images,
  files` (`text` covers rich text, colors and code).
- `ClipRepresentation` — one pasteboard type of a clip (`type`, `data`).
  `PasteboardItem` — one pasteboard item: its representations in order.
  Whether bytes live inline or in a blob file is the store's business.
- `PasteboardSnapshot` — platform-neutral copy of what's on the pasteboard:
  ordered `items`, `changeCount`, `sourceBundleID` (resolve it with
  `sourceBundleID(marker:frontmost:)`: `org.nspasteboard.source` first, then
  the frontmost app). The app builds it from `NSPasteboard`; tests by hand.
- `CaptureSettings` — the capture-related preferences as a plain value, so
  policy and builder stay pure (`Preferences.captureSettings`).
- `CapturePolicy` — pure: `decision(types:sourceBundleID:)` →
  `.record` / `.ignore(IgnoreReason)` (`paused`, `ownWrite`, `concealed`,
  `transient`, `autoGenerated`, `remoteClipboard`, `excludedApp`,
  `kindDisabled`, `empty`). Checked on **types before data is read**.
- `ClipBuilder` — pure and `Sendable`: `build(from:) -> ClipDraft?`. Keeps
  only `PasteboardType.captured`, enforces `maxItemBytes` (drops the
  heaviest non-primary representations first; `nil` if the primary payload
  alone is too big), detects the kind, derives title, search text, metadata
  and hash. Image sizes come from an injected `ImageInspecting` (core reads
  PNG; the app adds ImageIO).
- `HistoryStore` — `@MainActor`, `@Observable`, `init(directory:limits:)`.
  Exposes `pinned` (pin order) and `recent` (unpinned, newest first) and
  mutations: `record(_:at:)` (dedup bumps to top), `markUsed(_:at:)`, `pin`,
  `unpin`, `movePin(_:toIndex:)`, `delete`, `clearUnpinned`, `clearAll`,
  `setHistoryLimit`, `representations(for:) -> [PasteboardItem]`. Prunes
  unpinned clips past the limit automatically (pins never); every error is
  a thrown `HistoryStoreError`.
- `ClipSearch` — pure: `results(for:filter:pinned:recent:) → [Clip]`.
  Case/diacritic-insensitive; every token must match; word-start >
  substring > subsequence (tokens ≥3 chars, near the start); ties by
  recency; an empty query lists pins first, then recent clips.
- `Preferences` — `@MainActor`, `@Observable` wrapper over an injected
  `UserDefaults`; every default and range lives in `PreferenceDefaults`.

### Storage layout

`<directory>/History.sqlite` (WAL, foreign keys, `secure_delete`) with two
tables: `clips` (summary columns, `content_hash` UNIQUE, `pin_order` NULL
when unpinned, metadata as JSON) and `representations` (`clip_id` → clips
ON DELETE CASCADE, `item_index`, `position`, `type`, inline `data` **or**
`blob_hash`, `size`). Payloads over 64 KB go to `<directory>/blobs/<sha256>`
(written atomically, 0600, in a 0700 folder); unreferenced blobs are deleted
after each delete and swept at launch. `PRAGMA user_version` counts applied
migrations (`HistorySchema`).

### Capture flow (app ↔ core)

1. On a `changeCount` change, read `types` and resolve the source app.
2. `CapturePolicy(settings: preferences.captureSettings).decision(types:sourceBundleID:)`.
3. On `.record`, read only `PasteboardType.captured` types of each item into
   a `PasteboardSnapshot` (resolve Finder's file reference URLs,
   `file:///.file/id=…`, to path URLs first).
4. `ClipBuilder(settings:imageInspector:).build(from:)` — off the main actor
   for large images — then `HistoryStore.record(_:)`.

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
