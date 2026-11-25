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
    Models/                   Clip, ClipDraft, ClipFilter, ClipKind, ClipMetadata, ClipRepresentation,
                              PasteboardItem, PixelSize
    Capture/                  PasteboardType, PasteboardSnapshot, CaptureSettings, CapturePolicy
                              (+ CaptureDecision, IgnoreReason), ClipBuilder, ImageInspecting /
                              PNGImageInspector, LinkDetector, ColorParser, CodeDetector, AppActivationLog
    Storage/                  HistoryStore (state, opening, loading, reading) + HistoryStore+Recording,
                              +Editing, +Pins, +Removing, +Rows; HistoryLimits, HistoryStoreError,
                              HistorySchema (migrations), BlobStore (+ BlobReservations), ClipStager
                              (+ StagedClip), StoredRepresentations; the internal SQLite wrapper
                              (SQLiteDatabase, SQLiteStatement, SQLiteValue; SQLiteError is public)
    Search/                   ClipSearch (matching, ranking, kind filter), SearchKey (folded text)
    Preferences/              Preferences (UserDefaults-backed), PreferenceDefaults (every default),
                              PanelPosition, PanelPlacement (where the panel goes), RetentionPeriod
    Support/                  SHA256, TextSanitizer, RTFTextExtractor, HTMLTextExtractor, LRUCache,
                              SharedLoads
  Kept/                       macOS app (executable target)
    App/                      main.swift, AppDelegate, AppEnvironment (composition root)
    Clipboard/                capture: PasteboardMonitor, PasteboardReader, CaptureService,
                              AppActivationTracker, ImageIOInspector, ImageTranscoder (+ DecodedImage);
                              paste: PasteService (+ ClipPasting), PastePolicy, PastePlan, PasteRequest,
                              PasteOptions, PasteboardWriter, ClipboardPlainText, KeystrokePosting /
                              PasteKeystrokePoster, KeyboardLayout, PasteKeyResolver, KeyTranslating /
                              UnicodeKeyLayout; NSPasteboardType+Kept (AppKit ↔ core pasteboard types)
    Permissions/              PermissionChecking / PostEventPermission, KeyboardFocusChecking /
                              SystemKeyboardFocus, PasteboardAccess, PasteboardAccessChecking /
                              SystemPasteboardAccess, PasteOnboarding
    PasteHint/                PasteHintController (+ PasteHintPresenting), HintPanel, PasteHintView,
                              PasteHintCopy
    Hotkeys/                  HotkeyController, KeyboardShortcuts+Names
    Panel/                    PanelController, FloatingPanel (NSPanel), PanelViewModel + PanelViewModel+Display,
                              +Actions, +Editing; PanelKeyRouter (+ KeyPress, KeyPress+Event, PanelCommand,
                              PanelKeyMode), PanelEditing, PanelResources, PreviewLoader (+ ClipPreview),
                              ClipMenu, ClipDisplay, ClipFacts, ClipAccessibility, MatchHighlighter, EmptyState
      Views/                  PanelView, SearchBar, ClipList, ClipRow, ClipSummary, ClipGlyph, RenameField,
                              PreviewPane, TextEditPane, ClipTextEditor, EmptyStateView, PanelFooter,
                              ClearConfirmationBar, EditingBar
    MenuBar/                  StatusItemController, StatusMenu (+ StatusMenuState), MenuBarIcon,
                              MenuBarIconPreference
    Settings/                 SettingsWindowController, SettingsWindow, SettingsTabViewController,
                              SettingsModel, SettingsPane; LoginItemControlling / MainAppLoginItem
                              (+ LoginItemStatus, LaunchAtLoginState); SettingsDialogPresenting /
                              SettingsDialogs (+ ClearHistoryPrompt, ClearHistoryChoice); ExcludedApp,
                              AboutInfo
      Views/                  SettingsPaneView, GeneralPane, ShortcutsPane, PrivacyPane, AboutPane,
                              ExcludedAppsList, SettingsForm, SettingsRow, SettingsNote
    Welcome/                  WelcomeWindowController, WelcomeView, WelcomeCopy, WelcomeState
    DesignSystem/             Theme (tokens), AdaptiveColor, Color+Hex, MarkerShape (the highlighter),
                              KeyCap, KeyHint, Hairline
    Snapshots/                debug builds only: SnapshotRenderer, SettingsSnapshots, SampleHistory
                              (`Kept --render-snapshots <dir>`)
    Support/                  IconCache, ThumbnailCache, AgeFormatter, Log, VoiceOver, RetentionScheduler,
                              ActiveAppTracker (+ FocusReturn)
Tests/
  KeptCoreTests/              Swift Testing (`import Testing`); runs on Linux + macOS
  KeptTests/                  macOS-only tests for app-layer logic that can't live in core
Resources/                    Info.plist, Kept.entitlements, AppIcon assets (copied by the bundle script)
scripts/                      build-app.sh (assembles + signs Kept.app from `swift build` output),
                              package.sh (release disk image, notarization), make-icon.py
Makefile                      build / test / app / run / release / clean
site/                         the product site: an Astro project of its own (see Website below)
.github/workflows/            ci.yml (macOS: build, test, snapshots, bundle, launch · Linux: core
                              tests), release.yml (published releases, then a site rebuild),
                              site.yml (the site: type-check, tests, build, output checks)
```

Resources are **not** SwiftPM `resources:`; the bundle script copies them into
`Kept.app/Contents/Resources` and code uses `Bundle.main`.

## Key types (KeptCore)

- `Clip` — one history entry, without its payload: `id` (UUID), `kind`,
  `title` (sanitized single line, ≤1,000 chars), `customTitle` (the name
  the user gave it, sanitized the same way, ≤200 chars; `nil` for none),
  `displayTitle` (the name, else the title), `searchText` (sanitized,
  ≤8 KB), `contentHash` (SHA-256 of the primary payload, the dedup key),
  `sourceBundleID`, `firstCopiedAt`, `lastCopiedAt`, `copyCount`, `pinOrder`
  (`nil` = not pinned; `isPinned`), `byteSize`, and `metadata`
  (`ClipMetadata`: character count, `looksLikeCode`, link host, color hex,
  image pixel size and type, file count). Each clip caches its folded search
  text (the name, a line break, then `searchText`), so searching never
  re-normalizes and finds a clip by its name too; folding non-ASCII text goes
  through per-Unicode-block tables built once (`SearchKey`), not Foundation.
- `ClipKind` — `.text`, `.richText`, `.link`, `.image`, `.file`, `.color`.
  Code-like text is `.text`/`.richText` with `metadata.looksLikeCode`, used
  only for rendering. `isTextLike` (all but images and files) is what can
  be edited as text. `ClipFilter` — `all, pinned, text, links, images,
  files` (`text` covers rich text, colors and code).
- `ClipRepresentation` — one pasteboard type of a clip (`type`, `data`).
  `PasteboardItem` — one pasteboard item: its representations in order;
  `plainText` is its text for plain-text pastes and the preview (string,
  else URL, else the text of its RTF, else of its HTML, through the core
  extractors), `plainText(of:)` joins items' texts, and
  `plainTextItems(of:)` is what a plain-text paste writes (each item's
  text as a string-only item, worked out once; `nil` when none has text).
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
  `kindDisabled`, `tooManyItems`, `empty`). Checked on **types before data
  is read**; `decision(for: snapshot)` checks the snapshot's `allTypes`
  again. `typesToRead(offered:)` is what to read from one item: the text
  types, file URLs when files are kept, and one image type
  (`PasteboardType.preferredImageType(in:)`: PNG, JPEG, HEIC, then TIFF)
  when images are kept. `maxItems` (1,000) caps a copy's items; Finder
  writes one per file, so bigger file copies are skipped, not cut.
- `AppActivationLog` — pure: which app was frontmost when (monotonic
  seconds), and `excludedApp(from:through:settings:)`, the first excluded
  app frontmost at any moment of a window (inclusive: the one in front at
  its start and every one activated during it).
  `excludedApp(from:polledAt:settings:)` checks through
  `lateNotificationAllowance` (0.25 s) after the poll, for the second
  check once activations queued behind the poll are logged.
- `ClipBuilder` — pure and `Sendable`: `build(from:) -> ClipDraft?`.
  Refuses any snapshot whose items or `declaredTypes` carry a concealed,
  transient or auto-generated marker (legacy ones too). Keeps only
  `PasteboardType.captured`, enforces `maxItemBytes` (drops the heaviest
  non-primary representations first; `nil` if the primary payload alone is
  too big), detects the kind (files, visible string, images, URL, then
  HTML/RTF text; rich text judged after the cap), derives title, search
  text, metadata and hash, and pre-hashes representations over 64 KB.
  `draft(forEditedText:)` describes typed text the same way (one plain
  string item, no size cap), for edits.
  Hashes are domain-separated: text is hashed as NFC with LF line endings,
  images as every primary image's digest in order, files as their URLs.
  Image sizes come from an injected `ImageInspecting` (core reads PNG; the
  app adds ImageIO). HTML/RTF extraction and text sanitizing are linear on
  hostile input, and every displayed character is capped at 16 scalars.
- `TextSanitizer` — `singleLine` and `searchable` (internal) collapse text
  for rows and search; public `multiline(_:maxUTF16Count:)` keeps spaces,
  tabs and line breaks (all as LF) for the preview, drops the same scalars,
  caps every character the same way and cuts on a character boundary by
  UTF-16 length; `lineCount(of:)` counts lines on UTF-8 bytes, as many as
  `multiline` shows (a CR and an LF with a dropped character between them
  are two breaks in both).
- `HistoryStore` — `@MainActor`, `@Observable`, `init(directory:limits:)`.
  Exposes `pinned` (pin order) and `recent` (unpinned, newest first) and
  mutations: `record(_:at:)` (dedup bumps to top; a `ClipDraft`, or a
  `StagedClip` whose blob files are already written), `discard(_:)` (a
  staged clip that won't be recorded), `markUsed(_:at:)`, `pin`,
  `unpin(_:at:)` (back to the top of the history), `movePin(_:toIndex:)`,
  `delete(_:at:)` (remembers when each of the last 64 deleted contents
  went, for `wasDeleted(_:after:)`), `clearUnpinned`, `clearAll` (both
  bump `clearGeneration`), `setHistoryLimit`, `forgetUnpinned(olderThan:)`
  (unpinned clips last copied before a cutoff; rows at once, unreferenced
  blob files on a background queue; returns how many went),
  `rename(_:to:)` (sets or clears `customTitle`; blank or the generated
  title clears; the clip stays in place) and `editText(_:to:at:)` (see
  below). `record` keeps a re-copied clip's name. Reading: `clip(withID:)`,
  `clip(withContentHash:)`, `representations(for:)` (every type) and
  `representations(for:types:)` (only those, so a text clip's text never
  loads the picture next to it), or `storedRepresentations(for:types:)`,
  which only queries the database and returns a `Sendable`
  `StoredRepresentations` whose `load()` reads blob files anywhere, off
  the main actor for big clips (`first(ofAny:)` narrows it to one
  representation). `stager` (`ClipStager`, `Sendable`) writes a draft's
  blob files off the main actor: `stageInBackground(_:)` on its own
  serial `DispatchQueue`, so fsyncs never hold a cooperative-pool thread.
  A staging that fails partway throws `ClipStager.Failure`, whose
  `written` goes to `discard(_:)` so no file waits for the next launch.
  Prunes unpinned clips past the limit automatically (pins never); every
  error is a thrown `HistoryStoreError`.
  Opening throws only when the history is unusable: unreadable rows are
  skipped and left alone (`skippedRecordCount`), and failed renumbering,
  pruning or blob sweeps at open land in `openWarnings`.
- `HistoryStore.editText(_:to:at:)` — replaces a text-like clip's content
  with plain text: one `.string` representation, kind, title, search text,
  metadata and hash from `ClipBuilder.draft(forEditedText:)` (text can
  become a link or a color and back; rich text loses its formatting). The
  clip keeps its ID, pin, name, copy count, source and dates. If another
  clip already holds the new content, the two merge into the edited one:
  it takes the other's pin when it has none (its place among the pins),
  its name when it has none, its copies (counts add up), the earlier first
  and later last copy; the other row goes. The old content is noted as
  deleted at `at`, so a capture of it seen before the edit and finished
  after is dropped (`wasDeleted`), while one made after records as usual;
  `clearGeneration` doesn't move, so other captures in flight still land.
  Large text goes through `stager.stage` first, so its blob is reserved.
  Images and files throw `.notEditable`, text with nothing visible
  `.emptyText`.
- `LRUCache` — a value type keeping the most recently used values within
  a count and a total cost (bytes). `SharedLoads` — `@MainActor`: one
  detached load per key at a time, shared by every caller asking for it;
  each caller waits on its own continuation, so a cancelled one gets `nil`
  at once, and a load nobody waits for any more is cancelled. The panel's previews and thumbnails use both.
- `ClipSearch` — pure: `results(for:filter:pinned:recent:) → [Clip]`.
  Case/diacritic-insensitive; every token must match; word-start >
  substring > subsequence (tokens of ≥3 typed characters, whole scalars,
  near the start); ties by recency; an empty query lists pins first, then
  recent clips.
- `Preferences` — `@MainActor`, `@Observable` wrapper over an injected
  `UserDefaults`; every default and range lives in `PreferenceDefaults`
  (including the history sizes Settings offers). Excluded apps are edited
  with `excludeApp`, `removeExcludedApps` and `restoreDefaultExcludedApps`
  (bundle IDs compare without regard to case, as capture compares them).
  `forgetAfter` is a `RetentionPeriod` (`never`, `day`, `week`, `month` =
  30 days; `cutoff(before:)`).
- `PanelPlacement` — pure: `frame(for:size:screens:mouse:statusItem:)` →
  the panel's frame for a `PanelPosition` (center of the screen under the
  pointer; top-left at the pointer; below the menu bar icon, leading edges
  lined up, falling back to the center when the icon isn't showing),
  clamped into the screen's visible frame with an 8 pt margin at the sides
  and bottom when it fits; too big a panel keeps its top on screen.

### Storage layout

`<directory>/History.sqlite` (WAL, foreign keys, `secure_delete`, 5 s busy
timeout; the database and its `-wal`/`-shm` files 0600, the folder 0700)
with two tables: `clips` (summary columns, `content_hash` UNIQUE,
`pin_order` NULL when unpinned, metadata as JSON) and `representations`
(`clip_id` → clips ON DELETE CASCADE, `item_index`, `position`, `type`,
inline `data` **or** `blob_hash`, `size`). Payloads over 64 KB go to
`<directory>/blobs/<sha256>` (0600, in a 0700 folder), written to a
temporary file, fsync'd and renamed before the row commits; an existing
file is reused only if its size and bytes match. Capture writes them off
the main actor (`ClipStager.stage`) and reserves their hashes first
(`BlobReservations`, a lock shared by every deletion), so a clear, delete
or sweep running meanwhile never removes a blob a clip is about to
reference; `record` releases the reservation (and `discard` deletes the
files a dropped clip, or a staging that failed partway, leaves
unreferenced). `record` writes a staged blob again only if its file has
gone. Unreferenced blobs are deleted after each delete and swept at launch
(temporary files only once they are 10 minutes old, and never one whose
date can't be read; a file a capture renamed away meanwhile isn't an
error; nothing when references can't be read).
Forgetting old clips (`forgetUnpinned`) deletes unreferenced blob files
on a utility queue (`BlobStore.removeInBackground`): the hashes are marked
first, and reserving one (every write a clip will reference reserves its
hash) takes its mark off, so a file a capture or edit uses again before
its turn is kept.
`PRAGMA user_version` counts applied migrations (`HistorySchema`): 1
created the tables, 2 added the nullable `clips.custom_title` (an
`ALTER TABLE`, so existing histories migrate in place).

### Capture flow (app ↔ core)

1. On a `changeCount` change, skip it if `AppActivationLog` says an
   excluded app was frontmost at any moment from the previous poll
   through this one (the app in front at the previous poll counts too);
   then read `types` and resolve the source app.
2. `CapturePolicy(settings: preferences.captureSettings).decision(types:sourceBundleID:)`.
3. On `.record`, skip copies of more than `CapturePolicy.maxItems` items,
   then read only `typesToRead(offered:)` of each item into a
   `PasteboardSnapshot`, passing every type as `declaredTypes`. All
   `NSPasteboard` calls stay on the main actor.
4. Off the main actor, in a detached task (at most two at once; a copy
   read while both are busy waits, and a newer one replaces it): resolve
   Finder's file reference URLs (`file:///.file/id=…`) to path URLs and
   re-encode TIFF-only images as PNG,
   `ClipBuilder(settings:imageInspector:).build(from:)`, then
   `HistoryStore.stager.stageInBackground(_:)` (blob files written and
   fsync'd on the stager's serial queue).
5. Back on the main actor, no sooner than 0.25 s after the poll,
   `HistoryStore.record(_ staged:at:)` writes the rows, unless the history
   was cleared (`clearGeneration`), the clip was deleted after its copy
   was seen (`wasDeleted(_:after:)`), the excluded-app check now finds an
   app (`excludedApp(from:polledAt:settings:)`) or the settings now refuse
   the clip, in which case `discard(_:)`.

## App layer

- **Composition root** — `AppEnvironment` creates the store, preferences,
  monitor, paste service and controllers once and injects them. No
  singletons beyond what AppKit forces.
- **PasteboardMonitor** — `Timer` on the main run loop every 0.5 s with
  0.15 s tolerance; compares `changeCount`; skips the change counts Kept
  wrote itself, everything while paused, and one change after "ignore next
  copy" (a toggle in the menu: `cancelIgnoreNextCopy()` takes it back). It
  never reads contents; it tells `CaptureService`, which reads
  `previousPollTime` (the change was made after it).
- **AppActivationTracker** — records `NSWorkspace` app activations in an
  `AppActivationLog` (on `ProcessInfo.systemUptime`), so capture can skip
  a copy if an excluded app was frontmost at any moment since the previous
  poll: a password manager's quick-access window that copies without a
  marker and hands focus straight back is caught, not attributed to the
  app it returned to. The source marker still names the source when present.
  Activations are timed when their notification is handled on the main
  thread, which may be just after a poll that was queued with it, hence
  the second check. The window is privacy-first: it's inclusive and counts
  the app in front at the previous poll, so a copy made within about half
  a second of leaving an excluded app (⌘-Tab out of 1Password, then ⌘C in
  Safari) is skipped too, as is one followed within 0.25 s of the poll by
  an excluded app coming to the front. Settings › Privacy says so.
- **PasteboardReader** — notes `changeCount`, asks `CapturePolicy` on the
  types and the frontmost app, reads `org.nspasteboard.source` and asks
  again, skips copies of more than 1,000 items, then reads only
  `CapturePolicy.typesToRead(offered:)` per item: one image type (a
  screenshot's 60 MB TIFF next to its PNG is never loaded), none when
  images are off, file URLs only when files are kept. If `changeCount`
  moved during the read, the read is dropped and the next poll takes the
  new copy. `NSPasteboard` isn't documented as thread-safe and may fetch
  promised data from the copying app (or a phone, for Universal
  Clipboard) while it's read, so reading stays on the main actor and
  everything after it doesn't. AppKit offers no way to learn a type's
  size before reading it.
- **CaptureService** — first checks the activation window, then runs the
  reader, then a detached task per copy: `PasteboardReader.normalized`
  (Finder file reference URLs resolved, TIFF-only images re-encoded to
  PNG), `ClipBuilder` (`ImageIOInspector` for sizes) and
  `HistoryStore.stager.stageInBackground` (blob files written and fsync'd
  on the stager's serial queue). At most `maxBuildsInFlight` (2) builds
  run side by side, so a slow one doesn't hold up the next copy and a
  burst can't pile up snapshots; a copy read while both are busy waits,
  and a newer copy replaces it (the newest is always recorded). Each is
  recorded on the main actor with the time its copy was seen, no sooner
  than 0.25 s after its poll, unless the same content was recorded more
  recently, the history was cleared since (`clearGeneration`), the clip
  was deleted since (`wasDeleted`), the activation window checked again
  now holds an excluded app, or pause, exclusions or kind toggles now
  refuse it (then its blob files are discarded, as are those of a staging
  that failed partway).
- **PasteboardWriter** — writes items back as `NSPasteboardItem`s with
  `.keptOwn`, `.source` and any privacy markers passed in. `PasteService`
  hands it all of a clip's representations, or
  `PasteboardItem.plainTextItems(of:)` of its text types, so an HTML-only
  clip pastes as text.
- **PanelController** — owns `FloatingPanel` (non-activating `NSPanel`,
  `.statusBar` level, `canBecomeKey = true`), places it with
  `PanelPlacement` (the setting for the shortcut, `.statusItem` for a click
  on the menu bar icon), shows it with
  `orderFrontRegardless(); makeKey()` so the target app stays frontmost
  (≤120 ms fade, none under Reduce Motion), hides on `resignKey`. The panel
  sees every key-down first (unless an input method is composing):
  `PanelKeyRouter` turns it into a `PanelCommand` (letters by
  `charactersIgnoringModifiers`, so shortcuts follow the layout) or lets it
  through to the search field. ⌘X/⌘C/⌘V/⌘A/⌘Z are sent to the field
  directly, since an agent app has no Edit menu.
- **PanelViewModel** — `@Observable`; holds query, filter, selection
  (`selectedID` and `selectedIndex`, plus `scrollToken`, which moves
  whenever the selected *row* does, so the list scrolls after pins, pin
  moves and new copies too); derives visible clips via `ClipSearch`;
  carries out commands (move, paste, pin, move a pin, delete, clear with
  an inline confirm, open Settings); refreshes when the store changes,
  except while the panel is hidden (`panelDidHide` also drops the query).
  Key presses go through `perform(_:)`, which leaves ⌘⌫ to the search
  field while there's a query and lets only ⌥⌘⌫ confirm the clear bar;
  the context menu uses `perform(_:on:)`, its items from `ClipMenu`
  (Rename… for every clip, Edit… for text-like ones). Renaming and editing
  live here too (`editing: PanelEditing?`, `nameDraft`, `textDraft`):
  ⌘R makes the row a `RenameField`; ⌘E reads the clip's plain text
  (detached when over 64 KB; refused past 100,000 characters, and for
  images and files with a footer note) and the preview becomes a
  `TextEditPane` around `ClipTextEditor` (an `NSTextView` with
  substitutions off). `keyMode` tells `PanelKeyRouter` how to read keys:
  while editing it hands typing, text navigation and the editing shortcuts
  to the field, maps ⏎ (renaming), ⌘S and ⌘⏎ to save and Esc to cancel,
  and takes every other ⌘ shortcut as `.ignore`. Moving away (another row,
  the query, the filter, the context menu, a double-click, hiding the
  panel, the field losing the keyboard) saves; only Esc discards.
  `searchFocusToken` gives the search field the keyboard back afterwards.
  Moving the selection asks `announce` (`VoiceOver.announce`, via
  `PanelController`, when VoiceOver is on) to speak the row's
  `ClipAccessibility` label. The list never reads the selection itself:
  each row does, and a small `SelectionScroller` view scrolls, so an arrow
  key doesn't rebuild every row. `MatchHighlighter` finds the query's
  words in a row's title for display (semibold runs, and an excerpt when
  the first match would be truncated). A row's context menu runs
  the same commands on the clicked clip (`perform(_:on:)`). Pins reorder
  (⌥⌘↑ / ⌥⌘↓, or dragging, `dragPin(_:toRow:)`) only while the list shows
  them in their own order (`canReorderPins`: no search, filter All or
  Pinned), so a pin's row is its place. Footer labels follow
  `PasteOptions`. Views only render it; caches (app icons, thumbnails)
  live in `PanelResources`. Its stored state is all in
  `PanelViewModel.swift` (so observation tracks it); what views read is in
  `+Display`, pasting, pins, deleting, clearing and filters in `+Actions`,
  and renaming and editing in `+Editing`.
- **RetentionScheduler** — applies `Preferences.forgetAfter`: at launch,
  whenever it changes (observation) and hourly on a timer with 10 minutes'
  tolerance (none with "Never"), `HistoryStore.forgetUnpinned(olderThan:)`
  with the period's cutoff.
- **PreviewLoader** — the view model's previews. It reads only what a
  preview shows (`representations(for:types:)`: a text clip's text types,
  a file clip's URLs), sanitizes all of it with
  `TextSanitizer.multiline` (20,000 UTF-16 units of text, 4,096 per file
  path) and counts lines on bytes. Clips whose shown representations are
  in the database and at most 64 KB are previewed at once; bigger ones
  show `.loading` while `load(_:)` reads and prepares them off the main
  actor (`SharedLoads`), cancelled when the selection moves on. The last
  16 previews are kept (`LRUCache`), keyed by ID, content hash and copy,
  so an edited clip is previewed afresh.
- **ThumbnailCache** — reads only a clip's own image representation and
  decodes it off the main actor (`SharedLoads`: one decode per image and
  size, cancelled when no view waits for it), keeping decoded images by
  byte cost, rows (16 MB) and previews (64 MB) apart, least recently used
  out first.
- **PasteService** — see the paste flow below. Depends on protocols
  (`PermissionChecking`, `KeystrokePosting`, `KeyboardFocusChecking`,
  `PasteHintPresenting`), so tests fake the system.
- **Snapshots** — debug builds only (`#if DEBUG`; `make app` builds
  release). `Kept --render-snapshots <dir>` fills a temporary store
  with `SampleHistory`, renders the panel, the copy-only hint and each
  Settings pane offscreen at 2× in light and dark (opaque background:
  vibrancy doesn't draw offscreen), draws the whole Settings window with
  its toolbar (light only: the toolbar's selection glass doesn't draw
  offscreen in dark mode), the welcome window's content, and a search
  under the Increase Contrast appearance, and exits. Settings render from
  a throwaway preferences domain and stand-ins for the login item,
  permission and dialogs. CI runs the debug binary and uploads the PNGs as
  the `panel-snapshots` artifact.
- **Menu bar** — `StatusItemController` owns the `NSStatusItem`: a click
  toggles the panel below the icon; a right-, ⌃- or ⌥-click
  (`wantsMenu(_:modifiers:)`, pure) attaches
  `StatusMenu` and calls `performClick` (replaying the mouse event broke
  on macOS 27), detaching it in `menuDidClose`. The menu is refreshed
  from `StatusMenuState` (a value: pause title, ignore-next-copy state)
  each time it opens; Open Kept and Pause capture show their recorded
  shortcuts (`NSMenuItem.setShortcut(for:)`), and global shortcuts are
  off while the menu tracks. "Clear history…" opens the panel with its
  inline confirmation, so no alert activates Kept.
- **Settings** — `SettingsWindowController` makes the window on first
  use: `SettingsWindow` (handles ⌘W and ⌘Q, as Kept has no main menu)
  around a `SettingsTabViewController` (`NSTabViewController`, toolbar
  style, one `NSHostingController` per `SettingsPane`). The window has a
  fixed width, takes the selected pane's preferred height with its top
  edge fixed, and remembers the last pane (UserDefaults `settingsPane`;
  `-settingsPane shortcuts` on the command line picks one). Showing it
  activates Kept (`NSApp.activate()`); closing it hands activation to the
  last app other than Kept that was active (`ActiveAppTracker`, from
  `NSWorkspace.didActivateApplicationNotification`), or hides Kept when
  there's none (`FocusReturn`, pure), unless another Kept window stays
  open. `SettingsModel` (`@Observable`) binds the
  panes to `Preferences` and adds what needs the system, behind
  protocols: `LoginItemControlling` (`MainAppLoginItem` →
  `SMAppService.mainApp`; status re-read whenever the window becomes key,
  mapped to `LaunchAtLoginState`'s checkbox, note and Login Items button),
  `PermissionChecking` (paste status and "Open Privacy & Security…"), and
  `SettingsDialogPresenting` (`SettingsDialogs`: an `NSOpenPanel` in
  /Applications for excluded apps, read with the user-selected read-only
  entitlement; an `NSAlert` sheet built from `ClearHistoryPrompt`). The
  history size applies live through `HistoryStore.setHistoryLimit`.
  `PasteboardAccessChecking` (`SystemPasteboardAccess`:
  `NSPasteboard.general.accessBehavior` on macOS 15.4+, mapped to
  `PasteboardAccess`) drives the clipboard note in Privacy and the
  welcome window; `MenuBarIconPreference` backs "Show Kept in the menu
  bar".
  About reads the version and build from the bundle (`AboutInfo`), the one
  place they live.
- **Welcome** — `WelcomeWindowController` (made by `AppDelegate`) shows
  `WelcomeView` once at the first launch (`WelcomeState`, UserDefaults
  `welcomeShown`) and from About. It reuses the Settings model (login item,
  clipboard access) and `ActiveAppTracker`; "Open Kept" waits for Kept to
  resign active before showing the panel. `PanelController.show` unhides
  Kept first, since closing a window with no app to return to hides it.
- **Escape hatches** — macOS 26 can hide the menu bar icon with no API to
  tell, so relaunching Kept (`applicationShouldHandleReopen`) turns
  `MenuBarIconPreference` back on (the icon can also be ⌘-dragged away or
  hidden in Settings; `StatusItemController` follows the preference and
  KVO on `isVisible` both ways) and opens Settings, ⌘, in the panel opens
  it, and the global shortcut keeps working.
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
3. It writes the clip (`PasteboardWriter`; for plain text only its text
   types are read, and each item's text worked out once), tells the
   monitor the change count (so the write is never captured) and marks
   the clip used. When a clip's text types add up to more than 64 KB, the
   panel first awaits `startLoading(_:for:)`, which reads them and works
   out the text in a detached task; another paste meanwhile does nothing,
   and hiding the panel drops this one. If the write fails the panel
   stays open with a notice; if only marking it used fails, that's logged
   and the paste goes ahead.
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
item's text (string, URL, RTF or HTML) as plain text with the original privacy
markers and source, and then follows steps 4–6 with no anchor (the hint
sits at the bottom of the active screen). Nothing textual → a beep.

## Website

`site/` is the product site, <https://kept.waseemsabir.com>: an Astro project
that builds to static HTML and ships one small script. It is not part of the
Swift package and shares no code with it. Three things it reads in place, so
each has one copy: the screenshots in `docs/images/`, the icon in
`Resources/Icon/` and the version in `Resources/Info.plist`.

- **Copy as data.** `site/src/data/` holds what the site says (features,
  privacy, shortcuts, questions, install steps, the demo's clips). The pages,
  the structured data for search engines and the Markdown and `llms.txt` files
  for AI assistants are all rendered from it. It repeats the README, so the
  two change together.
- **The live panel** on the home page is the panel rebuilt in HTML from
  DESIGN.md's tokens and `SampleHistory`'s clips, driven by dependency-free
  TypeScript in `site/src/scripts/panel/`. Its matching, highlighting and
  ordering mirror `ClipSearch`, `MatchHighlighter` and `HistoryStore` and
  are tested with Node's runner; a change to those rules in the app should
  be repeated there.
- **The download button** asks GitHub for the latest release when the site
  builds (`site/src/data/release.ts`) and falls back to `Info.plist`.
- **Publishing.** Vercel's Git integration builds `site/` on pushes to
  `master` that change it (`site/vercel.json`; `site/scripts/vercel-ignore.sh`
  decides), and gives pull requests a preview. The `Site` workflow checks the
  same build in CI, and the release workflow's last job calls a Vercel deploy
  hook so the button offers the new version. `site/README.md` has the setup.

## Conventions

- Swift 6 language mode, strict concurrency. UI and stores are `@MainActor`.
- No force unwraps outside tests; errors are typed and surfaced, not
  swallowed.
- Each file has one primary type, named after it; small private helpers
  (a row's subviews, a value only that type produces) may sit beside it.
  Folders mirror the layout above.
- A type too big for one file keeps its stored properties in `Type.swift`
  and its behavior in `Type+Concern.swift` extensions (`HistoryStore`,
  `PanelViewModel`); those extensions are `@MainActor` like the type, and
  the state they write has an internal rather than a private setter.
  Extensions of other modules' types are named the same way
  (`Color+Hex.swift`, `KeyboardShortcuts+Names.swift`).
- `KeptCore`'s `public` API is what the app needs; implementation
  details (the SQLite wrapper, row writing, blob bookkeeping) stay
  internal, and tests reach them with `@testable import KeptCore`.
- Pure logic goes in `KeptCore` with tests. App-layer code stays thin.
- Developer tools (the snapshot renderer) compile only in debug builds.
- Minimum macOS 14. Sandboxed (`com.apple.security.app-sandbox`).
