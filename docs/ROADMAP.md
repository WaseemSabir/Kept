# Kept — Roadmap

Living checklist. Each milestone is built, tested (Linux unit tests for
`KeptCore`, macOS CI build for the app) and committed to `master` before the
next one starts. Look and feel come from [DESIGN.md](DESIGN.md); structure
from [ARCHITECTURE.md](ARCHITECTURE.md).

M0–M9 are the planned milestones. A1–A5 in the notes name the passes that
built them: A1 capture and the panel, A2 pasting, A3 Settings and the menu
bar, A4 onboarding and polish, A5 renaming, editing and forgetting.

Marks: ☐ todo · ◐ in progress · ☑ done

## Status

**0.1 is feature-complete.** It includes:

- **Capture:** text, rich text, links, colors, images and files, read off
  the main actor; privacy markers, excluded apps (also a moment around using
  them), Universal Clipboard, pause and "Ignore next copy" respected.
- **History:** SQLite with a blob store for big payloads; dedup, pins
  (reordered by key or drag), names (⌘R), text edits (⌘E), delete, clear,
  a size limit and "Forget unpinned clips".
- **Panel:** ⇧⌘V anywhere; search with marked matches, type filters, a
  preview with facts, ⌘1–9, a context menu, and the keyboard for everything.
- **Paste:** straight into the app you were in (layout-aware ⌘V), as plain
  text, or copy only; a hint and a one-time explanation when Kept can't
  paste; a global "Paste clipboard as plain text" shortcut.
- **Around it:** Settings, the menu bar icon and menu, the welcome window,
  launch at login, VoiceOver, Reduce Motion, Reduce Transparency and
  Increase Contrast.
- **Project:** CI on macOS (build, tests, snapshots, bundle, launch) and
  Linux (core tests); universal release builds, signed and notarized when
  credentials are set. A last structure pass split `HistoryStore` and
  `PanelViewModel` into extensions by concern, kept the SQLite wrapper
  internal to `KeptCore` and left the snapshot renderer out of release
  builds.

Not in 0.1: pruning by total blob size (only the clip count and the
per-clip cap limit the history) and everything under [Later](#later-p2-only-if-it-stays-lean).

### Check by hand on a Mac

CI can't grant permissions, post key events, run VoiceOver or change System
Settings, so check these on macOS 14, 15, 26 and 27 before a release. Sign
local builds with one persistent identity: an ad-hoc rebuild loses the paste
permission ([RELEASING.md](RELEASING.md#local-builds-use-one-persistent-self-signed-identity)).

- ☐ Pasting: ⌘V lands in the app you were in; the system prompt on the first
  paste; the copy-only hint, with and without "Allow Kept to paste…"; secure
  input (a password field, Terminal's Secure Keyboard Entry) copies and says
  "Press ⌘V".
- ☐ VoiceOver: row labels, the announcements as the selection moves, the
  hint, the rename field, and "Renamed to…" / "Edit saved."
- ☐ Menu bar icon: ⌘-drag it out of the menu bar, then bring it back from
  Settings and by opening Kept again.
- ☐ Focus: closing Settings or the welcome window gives the keyboard back to
  the last app, with and without another app to go back to.
- ☐ Clipboard access (macOS 15.4+): "Ask" and "Deny" under Paste from Other
  Apps show the note in the welcome window and in Settings › Privacy.
- ☐ Renaming: ⌘R's field takes the keyboard with its text selected; ⏎
  saves, Esc cancels, clicking elsewhere saves.
- ☐ Editing: ⌘E's editor takes the keyboard; the search field gets it back
  after saving or cancelling; clicking the search field while editing saves.

## M0 — Foundation
- ☑ Swift package: `KeptCore` (Foundation-only, Linux-testable), `CSQLite`, `Kept` app (macOS-only targets)
- ☑ App skeleton: agent app (`LSUIElement`), status item, empty panel toggled from the status item
- ☑ `scripts/build-app.sh` assembles a sandboxed, ad-hoc-signed `Kept.app`; `Makefile` (`build`, `test`, `app`, `run`)
- ☑ CI: macOS build + tests + app bundle; Linux core tests
- ☑ README, LICENSE (MIT), CLAUDE.md conventions

Notes:
- Also done early: the ⇧⌘V hotkey (KeyboardShortcuts 3.x) and the `Theme` tokens; a thin
  `SQLiteDatabase`/`SQLiteStatement` wrapper with smoke tests (M1 grows it into the store).
- Relaunching Kept showed the panel at first; A3 (M7) switched that to opening Settings.
- `Package.resolved` is not tracked: SwiftPM on Linux deletes it because the only
  dependency is macOS-only. KeyboardShortcuts is pinned with `from: "3.1.0"`.
- `build-app.sh` builds with `--build-system swiftbuild` and copies dependencies' resource
  bundles to `Contents/Resources`, where Swift Build's `Bundle.module` looks. (The native
  build system, still the default in Swift 6.3, looks only at the `.app` root and the
  build folder.) Confirmed in A3: CI checks the bundle holds the recorder's strings and opens
  Settings on the Shortcuts pane in the bundled app with `.build` moved away.

## M1 — History store (core)
- ☑ SQLite wrapper + schema + migrations (`clips`, `representations`)
- ☑ Content-addressed blob store for large payloads (images, RTF/HTML)
- ☑ Record with dedup (re-copy bumps to top, counts copies)
- ☑ Pins (never pruned, manual order), delete, clear unpinned
- ☑ Pruning: item limit (default 500 unpinned), per-item size cap, orphan blob cleanup

Notes:
- Payloads over 64 KB go to `blobs/<sha256>`; smaller ones stay inline in SQLite. The per-item
  cap (20 MB) is enforced by `ClipBuilder`, which drops the heaviest non-primary
  representations first. Pruning by total blob size (~500 MB) isn't done yet.
- New pins go to the end of the pinned section; `pinOrder` stays 0…n-1.
- `representations(for:)` returns `[PasteboardItem]` (typed items, not tuples).
- Also done here: `ClipSearch` (M3) and the `Preferences` model (M6), both in core.
- Core review fixes (after M1/M2): opening skips unreadable rows (`skippedRecordCount`) and
  reports failed housekeeping in `openWarnings` instead of throwing; blob files are fsync'd
  before rename and verified before reuse; database files 0600, folders 0700, 5 s busy
  timeout; unpinning moves a clip to the top (`unpin(_:at:)`); the item cap tops out at
  100 MB. Search folding is table-based (10,000 short accented/Cyrillic clips fold in ~20 ms
  in release) and fuzzy matching counts typed characters and matches whole scalars.

## M2 — Clipboard capture
- ☑ `PasteboardSnapshot` + `CapturePolicy` (core): nspasteboard.org markers, legacy password types, excluded apps, whitespace-only, size caps, skipped heavy types
- ☑ Primary kind detection: text / rich text / link / image / file(s) / color
- ☑ `PasteboardMonitor` (app): `changeCount` polling with tolerance, source app (`org.nspasteboard.source` → frontmost app)
- ☑ Skip Kept's own writes; pause capture; ignore next copy — core: `app.kept.Kept.own` marker and pause in `CapturePolicy`; app: own change counts, pause, one-shot ignore (the menu item and shortcut came with M6/M7)
- ☑ Default excluded apps (Passwords, Keychain Access, 1Password 7/8, Bitwarden, KeePassXC) in `PreferenceDefaults`

Notes:
- `PasteboardSnapshot.sourceBundleID(marker:frontmost:)` resolves the source app; the app
  must resolve Finder's file reference URLs (`file:///.file/id=…`) before building a clip.
- Core reads PNG sizes only; the app supplies an ImageIO `ImageInspecting` for TIFF/JPEG/HEIC.
- `ClipBuilder` is pure and `Sendable`; run it off the main actor for large images (pure-Swift
  SHA-256 hashes ~220 MB/s in release). It pre-hashes representations over 64 KB, which
  `HistoryStore.record` reuses as blob names.
- Defence in depth: the reader passes `NSPasteboard.types` as `declaredTypes`, and both
  `CapturePolicy.decision(for:)` and `ClipBuilder` refuse privacy markers found there.
- Dedup hashes: text as NFC with LF line endings; every primary image in order; images beat a
  bare `public.url`. Colors need ASCII hex; `#RGB`/`#RGBA` only when mixing digits and letters
  or repeating one digit, so `#123` and `#cafe` stay text.
- HTML/RTF extraction and the text sanitizer are linear on hostile input (tested with lone
  `<`, unclosed comments, deep RTF nesting, joiner/tag/skin-tone chains, multi-MB lines).

## M3 — The panel
- ☑ Non-activating floating `NSPanel` hosting SwiftUI; centered on the active screen (M0)
- ☑ Global hotkey ⇧⌘V (KeyboardShortcuts) toggles the panel (M0)
- ☑ Search field (always focused), live filtering, fuzzy-ish matching — core `ClipSearch` (M1): 5,000 clips in ~4 ms per query (release)
- ☑ List with quick-paste numbers, pinned section, kind-aware rows (swatch, thumbnail, host/path, mono for code)
- ☑ Preview pane with facts (source, copied, size)
- ☑ Footer with shortcut hints; empty states
- ☑ Design tokens (`Theme`) and highlighter selection
- ☑ Keyboard: ↑/↓ ⌃N/⌃P, ⌘↑/⌘↓, PgUp/PgDn, Esc (clear → close), ⌃U, Tab/⇧Tab type filter

Notes:
- Capture (M2) and the panel (M3) landed together as A1. `CaptureService` builds clips off
  the main actor, side by side, so a slow image never holds up later copies; a read is dropped
  if `changeCount` moves while it runs (privacy race), and the next poll takes the new copy.
- The panel routes every key-down through `PanelKeyRouter` before the search field sees it
  (except while an input method composes); letters match `charactersIgnoringModifiers`.
  ⌘X/⌘C/⌘V/⌘A/⌘Z are sent to the field by hand, since an agent app has no Edit menu.
- At this point ⏎ / ⌥⏎ / ⌘⏎ / ⌘1–9 / ⌥⌘1–9 only copied and closed; M4 added pasting.
- `Kept --render-snapshots <dir>` rendered 13 panel states × light/dark at first (the hint,
  Settings and the welcome window came later); CI uploads them as the `panel-snapshots`
  artifact. It's in debug builds only.

## M4 — Paste
- ☑ Write a clip back to the pasteboard (all representations / plain text only)
- ☑ Synthesize ⌘V into the previous app (layout-aware key code), skip own write in monitor
- ☑ ⏎ paste · ⌥⏎ plain · ⌘⏎ copy only · ⌘1–9 · ⌥⌘1–9 · double-click; "always paste plain text" swaps ⏎/⌥⏎
- ☑ Permission: `CGPreflightPostEventAccess` / request on first paste; copy-only fallback with hint
- ☑ Global "paste clipboard as plain text" shortcut (no default)

Notes:
- A2. `PastePolicy` (pure, tested over every combination) decides format and delivery:
  ⌘⏎ or "paste directly" off copy quietly; Kept frontmost or secure input copy with
  "Press ⌘V"; no PostEvent access copies, calls `CGRequestPostEventAccess()` once and shows
  the "Allow Kept to paste…" hint once, then only "Copied. Press ⌘V to paste." Both are
  remembered in UserDefaults (`pasteAccessRequested`, `pastePermissionHintShown`).
- The ⌘V key is resolved under ⌘ first, so layouts that switch to QWERTY while ⌘ is held
  ("Dvorak – QWERTY ⌘") paste with QWERTY's V; non-Latin layouts use the ASCII-capable
  layout's V; `kVK_ANSI_V` is the last resort. Posted 50 ms after the panel hides.
- With "paste directly" off the footer says "Copy" / "Copy as plain text" (an honest label);
  with it on, the footer also shows "⌘⏎ Copy".
- The plain-text shortcut keeps privacy markers and the source app when it rewrites the
  clipboard, and records a copy the monitor hasn't polled yet before replacing it.
- CI can't post events or grant TCC access, so the real ⌘V, the system prompt and the
  hint window need a hand check on macOS 14/15/26/27 (ad-hoc builds lose the permission on
  every rebuild: TCC keys it to the code hash).

## M5 — Pins & cleanup
- ☑ ⌘P pin/unpin, pinned section order, reorder pins (drag, or ⌥⌘↑ / ⌥⌘↓ on the selected pin)
- ☑ ⌘⌫ delete, ⌥⌘⌫ clear unpinned (inline confirm bar, no modal)
- ☑ Right-click context menu on rows (paste, paste as plain text, copy, pin/unpin, delete)

## M6 — Settings
- ☑ Settings window (owned `NSWindow`, toolbar panes General · Shortcuts · Privacy · About)
- ☑ General: launch at login (`SMAppService`), history size, paste directly vs copy only, always paste plain text, panel position (center / pointer / below the menu bar icon)
- ☑ Shortcuts: open Kept, paste clipboard as plain text (no default), pause capture (no default) — `KeyboardShortcuts.Recorder`
- ☑ Privacy: pause, excluded apps (+/−, defaults), ignore Universal Clipboard, keep images / files, clear history (keep pins or clear everything)
- ☑ About: icon, version and build from the bundle, license, project link, history health note

## M7 — Menu bar & app identity
- ☑ Left-click toggles panel (below the icon); right-click / ⌃-click / ⌥-click menu (Open Kept, Pause/Resume capture, Ignore next copy, Clear history…, Settings…, Quit)
- ☑ Custom template menu bar glyph; dimmed when paused — glyph + paused variant drawn (`MenuBarIcon`); follows `Preferences.isPaused` (A2)
- ☑ App icon — "the marked line" (`Resources/Icon/*.svg` → `scripts/make-icon.py` → `Resources/AppIcon.icns`)
- ☑ Reopen (launching again) opens Settings — escape hatch if the menu bar icon is hidden; ⌘, in the panel too

Notes (M5–M7, A3):
- Settings is an `NSTabViewController` in toolbar style hosting one SwiftUI view per pane, in
  the classic two-column layout (right-aligned labels); the window keeps a fixed width, takes
  each pane's height (top edge fixed) and remembers the last pane (`settingsPane` default).
  Opening it activates Kept; closing it hands focus back to the app that was in front.
- Launch at login reads `SMAppService.mainApp.status` whenever Settings becomes key; a failed
  register (common for unsigned builds) or `.requiresApproval` shows a note and an
  "Open Login Items…" button.
- Panel placement is pure (`PanelPlacement` in core, tested on Linux) and clamped to the
  screen's visible frame. Clicking the menu bar icon always opens the panel below it; the
  setting decides where the shortcut opens it, falling back to the active screen's center
  when the icon is hidden.
- "Clear history…" in the menu opens the panel's inline confirmation (no alert, no
  activation); the one in Settings asks with an alert and offers keeping pins or clearing
  everything.
- The menu shows the recorded shortcuts (`NSMenuItem.setShortcut(for:)`) and disables global
  shortcuts while it tracks, so a queued hot key doesn't fire when it closes. It opens with
  `performClick` on the button, not by replaying the mouse event (broken on macOS 27).
- The version lives only in `Resources/Info.plist`; `KeptVersion` is gone.

## M8 — Images & files polish
- ☑ TIFF → PNG re-encode, thumbnails (`CGImageSource`), image size cap
- ☑ File icons and multi-file items; preview of images and files

Notes (review fixes: robustness, privacy, performance):
- Capture reads one image type per item (PNG, JPEG, HEIC, then TIFF), none when images
  are off, and skips copies of more than 1,000 items (`CapturePolicy.maxItems`). File
  reference resolution, TIFF → PNG, building, hashing and blob writes (with fsync) all run
  in the detached build task; blobs are reserved so a clear or delete in between can't
  remove them. `NSPasteboard` reads stay on the main actor (not documented thread-safe).
- A build that finishes after the history was cleared, or after pause, an exclusion or a
  kind toggle changed, is dropped with its blob files.
- An excluded app frontmost at any moment since the previous poll stops a copy
  (`AppActivationLog`), so quick-access windows that copy and hand focus back are caught.
- The preview sanitizes all text and file paths (`TextSanitizer.multiline`: line breaks
  kept, every character capped at 16 scalars, 20,000 UTF-16 units), reads only the types it
  shows, counts lines on bytes, loads big clips off the main actor with cancellation and
  keeps the last 16. Thumbnails read one representation off the main actor, share loads,
  and are bounded by bytes (16 MB rows, 64 MB previews).
- Plain text (⌥⏎, the global shortcut, the preview) comes from `PasteboardItem.plainText`:
  string, URL, RTF, then HTML, so HTML-only clips work. A failed "mark used" no longer
  stops a paste. "Ignore next copy" is a toggle.
- Capture follow-ups: at most two builds at once (a waiting copy is replaced by a newer
  one), blob writes on the stager's serial queue, the excluded-app window checked again
  0.25 s after the poll (activations queued behind a busy main thread), deleted clips
  stay deleted when a re-copy was building, a staging that fails partway deletes what it
  wrote, and a clear during a capture no longer reports a false error. Big plain-text
  pastes work out their text once, off the main thread; a cancelled preview load lets
  its caller go at once; preview line counts match the lines shown. Settings › Privacy
  says copies made within a moment of using an excluded app are skipped too.

## M9 — Onboarding, accessibility, release
- ☑ First-launch welcome window (where Kept is, the recorded shortcut, the paste permission, open at login; again from About)
- ☑ First-paste permission: version-aware copy-only hint with "Allow Kept to paste…" (A2)
- ☑ Pasteboard privacy check (`accessBehavior`, macOS 15.4+): ask / deny shows where to allow Kept, in the welcome window and Settings › Privacy
- ☑ VoiceOver labels and announcements; Reduce Motion / Transparency / Increase Contrast
- ☑ Snapshot renders of the panel for design review in CI (`Kept --render-snapshots <dir>`, artifact `panel-snapshots`)
- ☑ Release workflow (ad-hoc → signed → notarized when secrets exist) — `release.yml`, `scripts/package.sh`, docs/RELEASING.md
- ☑ README screenshots (`docs/images/`)

Notes (A4, UI/UX fixes and polish):
- Closing Settings (or the welcome window) gives the keyboard to the last app other than Kept
  that was active (`ActiveAppTracker`, from `NSWorkspace.didActivateApplicationNotification`),
  or hides Kept when there's none (`FocusReturn`). Before, relaunching Kept and closing
  Settings left Kept active with no window, and ⇧⌘V + ⏎ only copied.
- The menu bar icon follows `showsMenuBarIcon` both ways: ⌘-dragging it out turns it off,
  Settings › General › "Show Kept in the menu bar" sets it, and relaunching Kept turns it on.
- Destructive keys: ⌘⌫ deletes a clip only with an empty search (otherwise it edits the
  field); the clear bar takes only ⌥⌘⌫ again or its button, never ⏎.
- The list scrolls on `scrollToken`, which moves with the selected *row* (pins, pin moves,
  new copies), from a small view of its own; rows read the selection themselves, so arrow keys
  don't rebuild a 10,000-row list. The selected index is stored. While the panel is hidden
  its query is dropped and history changes don't run a search.
- VoiceOver: one element per row with a sentence label and a default Paste action; moving the
  selection is announced ("…, 9 minutes ago, from Safari. 4 of 15."). The list's selected
  child isn't exposed as such (SwiftUI has no API for it); announcements stand in.
- Matched query words are semibold in row titles, and a row whose first match would be
  truncated starts just before it. In dark mode the marker is a near-opaque yellow
  (`#F2CC47` @ 94%) under dark ink (`#1C1C1E`), like a real highlighter and the app icon; every
  marked text clears 4.5:1 in both modes.
- Excluded password managers that aren't installed show their names. The welcome window,
  clipboard access note and an Increase Contrast scene are in the snapshots.
- Needs a hand check on a Mac: VoiceOver announcements, the menu bar icon's ⌘-drag and
  restore, focus after Settings with and without another app, and `accessBehavior` on 15.4+
  (CI can't change it).

## A5 — Rename, edit and forget
- ☑ Core: schema 2 adds `custom_title` (schema 1 histories migrate in place); `Clip.customTitle` / `displayTitle`; search matches names too
- ☑ Core: `HistoryStore.rename(_:to:)` (sanitized, ≤200 characters; blank or the generated title clears) and `editText(_:to:at:)` for text, rich text, links and colors (kind, title, metadata and hash worked out again; ID, pin, name, copies and dates kept; merges into an existing clip with the same content)
- ☑ Core: retention — `Preferences.forgetAfter` (never / a day / a week / a month) and `HistoryStore.forgetUnpinned(olderThan:)`; pins exempt, blob files deleted on a background queue
- ☑ ⌘R renames inline in the row (⏎ saves, Esc cancels, empty restores the text, clicking away saves); named rows show the name, then the content muted
- ☑ ⌘E edits the text in the preview (⌘S / ⌘⏎ save, Esc cancels; mono for code, links and colors; rich text says it drops formatting); images and files point to ⌘R
- ☑ Context menu: Rename… and Edit… (text only); VoiceOver reads names and announces saves
- ☑ Settings › Privacy: "Forget unpinned clips", applied at launch, on change and hourly
- ☑ Snapshots: named row, renaming, editing prose / code / rich text, the image refusal, Privacy with the popup

Notes (A5):
- While a name or text is edited, `PanelKeyRouter` reads keys in a `PanelKeyMode`: the field
  gets typing, text navigation (⌘ with arrows, ⌫, ⌦) and the editing shortcuts; ⏎ (renaming),
  ⌘S and ⌘⏎ save; Esc cancels the edit, never the panel; every other ⌘ shortcut is taken and
  does nothing, so ⌘1–9 can't paste and ⌘P can't pin meanwhile.
- Moving away saves, as in Finder: clicking another row, searching, changing the filter, the
  context menu, double-clicking or closing the panel. Only Esc throws an edit away. An empty
  text edit stays open with a notice when saved with ⌘S, and is dropped (with a notice) when
  you move away.
- The editor is an `NSTextView` (no smart quotes, dashes, replacements, autocorrection or link
  detection; spelling checked for prose only). It shows the text as the preview does
  (`TextSanitizer.multiline`), so invisible control characters a clip held are gone once it's
  saved; saving the text unchanged writes nothing. Clips over 100,000 characters aren't
  edited; text over 64 KB is read off the main actor first.
- An edit remembers the old content as deleted at the edit (`wasDeleted`), so a copy of it seen
  before the edit can't come back as its own clip; the clear generation doesn't move. A merge
  keeps the edited clip's ID and takes the other's pin (when it had none), name (when it had
  none), copies, earlier first copy and later last copy. Re-copying a named clip keeps its name.
- Forgetting deletes rows on the main actor and blob files on a utility queue
  (`BlobStore.removeInBackground`); a blob reserved again before its turn (a capture or an edit
  with the same bytes) keeps its file. Forgotten content isn't remembered as deleted.
- Needs a hand check on a Mac: the rename field takes the keyboard with its text selected, the
  editor takes it on ⌘E, the search field gets it back after saving or cancelling, clicking
  the search field while editing saves, and VoiceOver hears the name field and the saves.

## Later (P2, only if it stays lean)
- Expose the panel's selected row to VoiceOver as the list's selected child (needs an AppKit
  list or a SwiftUI API for it)
- A deep link to the Paste from Other Apps pane, once macOS documents one
- OCR text in images for search
- Paste stack / multi-paste
- Ignore by regex; App Intents

## Out of scope
Sync, iOS, AI, text transforms, pinboards/collections, themes beyond light/dark,
snippet expansion, plugins, telemetry.
