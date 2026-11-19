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
    Preferences/              Preferences (UserDefaults-backed), PreferenceDefaults (every default), PanelPosition,
                              PanelPlacement (where the panel goes for each position)
    Support/                  SHA256, TextSanitizer, RTF/HTML text extractors
  Kept/                       macOS app (executable target)
    App/                      main.swift, AppDelegate, AppEnvironment (composition root)
    Clipboard/                PasteboardMonitor, PasteboardReader, CaptureService, PasteboardWriter,
                              ImageIOInspector, ImageTranscoder; paste: PasteService (+ ClipPasting),
                              PastePolicy, PastePlan, PasteRequest, PasteOptions, ClipboardPlainText,
                              KeystrokePosting / PasteKeystrokePoster, KeyboardLayout, UnicodeKeyLayout,
                              PasteKeyResolver (+ KeyTranslating)
    Permissions/              PermissionChecking / PostEventPermission, KeyboardFocusChecking /
                              SystemKeyboardFocus, PasteOnboarding (later: PasteboardAccess)
    PasteHint/                PasteHintController (+ PasteHintPresenting), HintPanel, PasteHintView, PasteHintCopy
    Hotkeys/                  KeyboardShortcuts.Name definitions + HotkeyController
    Panel/                    FloatingPanel (NSPanel), PanelController, PanelViewModel, PanelKeyRouter
                              (+ KeyPress, PanelCommand), ClipDisplay, ClipFacts, PreviewLoader, Views/
    MenuBar/                  StatusItemController, MenuBarIcon
    Settings/                 SettingsWindowController, Views/ (panes)
    DesignSystem/             Theme (tokens), AdaptiveColor, Marker (highlighter), KeyCap, Hairline
    Snapshots/                SnapshotRenderer, SampleHistory (`Kept --render-snapshots <dir>`)
    Support/                  IconCache, ThumbnailCache, AgeFormatter, RichTextDecoder, Log
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
  text, so searching never re-normalizes; folding non-ASCII text goes
  through per-Unicode-block tables built once (`SearchKey`), not Foundation.
- `ClipKind` — `.text`, `.richText`, `.link`, `.image`, `.file`, `.color`.
  Code-like text is `.text`/`.richText` with `metadata.looksLikeCode`, used
  only for rendering. `ClipFilter` — `all, pinned, text, links, images,
  files` (`text` covers rich text, colors and code).
- `ClipRepresentation` — one pasteboard type of a clip (`type`, `data`).
  `PasteboardItem` — one pasteboard item: its representations in order.
  Whether bytes live inline or in a blob file is the store's business.
  Internally it can carry the SHA-256 `ClipBuilder` computed off the main
  actor (cleared when `data` changes, not part of equality), which the store
  reuses as the blob name.
- `PasteboardSnapshot` — platform-neutral copy of what's on the pasteboard:
  ordered `items`, `changeCount`, `sourceBundleID` (resolve it with
  `sourceBundleID(marker:frontmost:)`: `org.nspasteboard.source` first, then
  the frontmost app), and `declaredTypes` (`NSPasteboard.types`, defaulting
  to the items' types; `allTypes` is both). The app builds it from
  `NSPasteboard`; tests by hand.
- `CaptureSettings` — the capture-related preferences as a plain value, so
  policy and builder stay pure (`Preferences.captureSettings`).
- `CapturePolicy` — pure: `decision(types:sourceBundleID:)` →
  `.record` / `.ignore(IgnoreReason)` (`paused`, `ownWrite`, `concealed`,
  `transient`, `autoGenerated`, `remoteClipboard`, `excludedApp`,
  `kindDisabled`, `empty`). Checked on **types before data is read**;
  `decision(for: snapshot)` checks the snapshot's `allTypes` again.
- `ClipBuilder` — pure and `Sendable`: `build(from:) -> ClipDraft?`.
  Refuses any snapshot whose items or `declaredTypes` carry a concealed,
  transient or auto-generated marker (legacy ones too). Keeps only
  `PasteboardType.captured`, enforces `maxItemBytes` (drops the heaviest
  non-primary representations first; `nil` if the primary payload alone is
  too big), detects the kind (files, visible string, images, URL, then
  HTML/RTF text; rich text judged after the cap), derives title, search
  text, metadata and hash, and pre-hashes representations over 64 KB.
  Hashes are domain-separated: text is hashed as NFC with LF line endings,
  images as every primary image's digest in order, files as their URLs.
  Image sizes come from an injected `ImageInspecting` (core reads PNG; the
  app adds ImageIO). HTML/RTF extraction and text sanitizing are linear on
  hostile input, and every displayed character is capped at 16 scalars.
- `HistoryStore` — `@MainActor`, `@Observable`, `init(directory:limits:)`.
  Exposes `pinned` (pin order) and `recent` (unpinned, newest first) and
  mutations: `record(_:at:)` (dedup bumps to top), `markUsed(_:at:)`, `pin`,
  `unpin(_:at:)` (back to the top of the history), `movePin(_:toIndex:)`,
  `delete`, `clearUnpinned`, `clearAll`, `setHistoryLimit`,
  `representations(for:) -> [PasteboardItem]`. Prunes unpinned clips past
  the limit automatically (pins never); every error is a thrown
  `HistoryStoreError`. Opening throws only when the history is unusable:
  unreadable rows are skipped and left alone (`skippedRecordCount`), and
  failed renumbering, pruning or blob sweeps at open land in `openWarnings`.
- `ClipSearch` — pure: `results(for:filter:pinned:recent:) → [Clip]`.
  Case/diacritic-insensitive; every token must match; word-start >
  substring > subsequence (tokens of ≥3 typed characters, whole scalars,
  near the start); ties by recency; an empty query lists pins first, then
  recent clips.
- `Preferences` — `@MainActor`, `@Observable` wrapper over an injected
  `UserDefaults`; every default and range lives in `PreferenceDefaults`.

### Storage layout

`<directory>/History.sqlite` (WAL, foreign keys, `secure_delete`, 5 s busy
timeout; the database and its `-wal`/`-shm` files 0600, the folder 0700)
with two tables: `clips` (summary columns, `content_hash` UNIQUE,
`pin_order` NULL when unpinned, metadata as JSON) and `representations`
(`clip_id` → clips ON DELETE CASCADE, `item_index`, `position`, `type`,
inline `data` **or** `blob_hash`, `size`). Payloads over 64 KB go to
`<directory>/blobs/<sha256>` (0600, in a 0700 folder), written to a
temporary file, fsync'd and renamed before the row commits; an existing
file is reused only if its size and bytes match. Unreferenced blobs are
deleted after each delete and swept at launch (temporary files only once
they are 10 minutes old; nothing when references can't be read).
`PRAGMA user_version` counts applied migrations (`HistorySchema`).

### Capture flow (app ↔ core)

1. On a `changeCount` change, read `types` and resolve the source app.
2. `CapturePolicy(settings: preferences.captureSettings).decision(types:sourceBundleID:)`.
3. On `.record`, read only `PasteboardType.captured` types of each item into
   a `PasteboardSnapshot`, passing every type as `declaredTypes` (resolve
   Finder's file reference URLs, `file:///.file/id=…`, to path URLs first).
4. `ClipBuilder(settings:imageInspector:).build(from:)` — off the main actor
   for large images — then `HistoryStore.record(_:)`.

## App layer

- **Composition root** — `AppEnvironment` creates the store, preferences,
  monitor, paste service and controllers once and injects them. No
  singletons beyond what AppKit forces.
- **PasteboardMonitor** — `Timer` on the main run loop every 0.5 s with
  0.15 s tolerance; compares `changeCount`; skips the change counts Kept
  wrote itself, everything while paused, and one change after "ignore next
  copy". It never reads contents; it tells `CaptureService`.
- **PasteboardReader** — notes `changeCount`, asks `CapturePolicy` on the
  types and the frontmost app, reads `org.nspasteboard.source` and asks
  again, then reads only `PasteboardType.captured` per item (Finder file
  reference URLs become path URLs). If `changeCount` moved during the read,
  the read is dropped and the next poll takes the new copy.
- **CaptureService** — runs the reader, then `ClipBuilder` in a detached
  task (TIFF-only images re-encoded to PNG first; `ImageIOInspector` for
  sizes). Builds run side by side, so a slow one never holds up later
  copies; each is recorded on the main actor with the time its copy was
  seen, unless the same content was recorded more recently.
- **PasteboardWriter** — writes a clip's items back as `NSPasteboardItem`s
  (all representations, or plain text only) with `.keptOwn`, `.source` and
  any privacy markers passed in.
- **PanelController** — owns `FloatingPanel` (non-activating `NSPanel`,
  `.statusBar` level, `canBecomeKey = true`), shows it with
  `orderFrontRegardless(); makeKey()` so the target app stays frontmost
  (≤120 ms fade, none under Reduce Motion), hides on `resignKey`. The panel
  sees every key-down first (unless an input method is composing):
  `PanelKeyRouter` turns it into a `PanelCommand` (letters by
  `charactersIgnoringModifiers`, so shortcuts follow the layout) or lets it
  through to the search field. ⌘X/⌘C/⌘V/⌘A/⌘Z are sent to the field
  directly, since an agent app has no Edit menu.
- **PanelViewModel** — `@Observable`; holds query, filter, selection;
  derives visible clips via `ClipSearch`; carries out commands (move,
  paste, pin, delete, clear with an inline confirm); refreshes when the
  store changes. Footer labels follow `PasteOptions`. Views only render
  it; caches (app icons, thumbnails) live in `PanelResources`.
- **PasteService** — see the paste flow below. Depends on protocols
  (`PermissionChecking`, `KeystrokePosting`, `KeyboardFocusChecking`,
  `PasteHintPresenting`), so tests fake the system.
- **Snapshots** — `Kept --render-snapshots <dir>` fills a temporary store
  with `SampleHistory`, renders the panel (and the copy-only hint) offscreen
  at 2× in light and dark (opaque background: vibrancy doesn't draw
  offscreen) and exits. CI runs it and uploads the PNGs as the
  `panel-snapshots` artifact.
- **Hotkeys** — `KeyboardShortcuts` package (Carbon `RegisterEventHotKey`
  under the hood; no permission prompt; recorder UI for settings).
  `HotkeyController` listens for `.togglePanel` (⇧⌘V), `.pastePlainText`
  and `.togglePause` (no defaults; the Settings recorder sets them).
  Pausing, from anywhere, swaps the menu bar glyph to its hollow marker.

### Paste flow

1. A key becomes a `PanelCommand` and then a `PasteRequest`: ⏎, ⌘1–9 and
   a double-click → `.paste(alternate: false)`; ⌥⏎ and ⌥⌘1–9 →
   `.paste(alternate: true)`; ⌘⏎ → `.copyOnly`. The global "paste
   clipboard as plain text" shortcut is `.clipboardAsPlainText`.
2. `PasteService.prepare` asks `PastePolicy` (pure) for a `PastePlan` from
   the request, `PasteOptions` and the conditions: PostEvent access
   (`CGPreflightPostEventAccess`), whether Kept already asked and already
   explained (`PasteOnboarding`, UserDefaults keys
   `pasteAccessRequested` / `pastePermissionHintShown`), Kept frontmost
   (`NSRunningApplication.current.isActive`) and secure input
   (`IsSecureEventInputEnabled`). Format: ⏎ writes the clip as copied, ⌥⏎
   plain text, swapped by "always paste plain text"; ⌘⏎ writes what ⏎
   would. Delivery, first match wins: ⌘⏎ or "paste directly" off → copy,
   no hint; Kept frontmost → copy + "Press ⌘V"; no access → copy, request
   access the first time, hint with the "Allow Kept to paste…" button the
   first time and "Press ⌘V" after; secure input → copy + "Press ⌘V";
   otherwise paste.
3. It writes the clip (`PasteboardWriter`), tells the monitor the change
   count (so the write is never captured) and marks the clip used. If the
   write fails the panel stays open with a notice.
4. The panel hides; then `complete` requests access
   (`CGRequestPostEventAccess`) if planned, posts ⌘V, or shows the hint
   near the panel's last frame.
5. `PasteKeystrokePoster` waits 50 ms (the panel has ordered out and the
   target app's window is key again), then posts key down/up from a
   `.combinedSessionState` source with local events suppressed, flags ⌘
   plus the left-⌘ device bit, to `.cgSessionEventTap`. The key code comes
   from `KeyboardLayout`: `PasteKeyResolver` asks the current layout, then
   the current ASCII-capable one, which key types "v" — with ⌘ held first
   (so "Dvorak – QWERTY ⌘" resolves to QWERTY's V), then without — and
   falls back to `kVK_ANSI_V`. Cached; dropped on
   `kTISNotifySelectedKeyboardInputSourceChanged`.
6. `PasteHintController` shows a borderless, non-activating `HintPanel`
   that never becomes key (its button takes the first click), fades in
   and out in 120 ms (not under Reduce Motion), stays 2.5 s (8 s with the
   button, longer while hovered) and is announced to VoiceOver. The button
   opens `x-apple.systempreferences:…?Privacy_Accessibility`, falling back
   to Privacy & Security. Opening the panel puts the hint away.

"Paste clipboard as plain text" hides the panel, polls the monitor (so a
copy made in the last half second is recorded first), rewrites each
item's text (string, URL or RTF) as plain text with the original privacy
markers and source, and then follows steps 4–6 with no anchor (the hint
sits at the bottom of the active screen). Nothing textual → a beep.

## Conventions

- Swift 6 language mode, strict concurrency. UI and stores are `@MainActor`.
- No force unwraps outside tests; errors are typed and surfaced, not
  swallowed.
- Each file has one primary type; folders mirror the layout above.
- Pure logic goes in `KeptCore` with tests. App-layer code stays thin.
- Minimum macOS 14. Sandboxed (`com.apple.security.app-sandbox`).
