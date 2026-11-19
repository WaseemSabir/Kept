# Kept — Roadmap

Living checklist. Each milestone is built, tested (Linux unit tests for
`KeptCore`, macOS CI build for the app) and committed to `master` before the
next one starts. Scope comes from [RESEARCH.md](RESEARCH.md); look and feel
from [DESIGN.md](DESIGN.md); structure from [ARCHITECTURE.md](ARCHITECTURE.md).

Status: ☐ todo · ◐ in progress · ☑ done

## M0 — Foundation
- ☑ Swift package: `KeptCore` (Foundation-only, Linux-testable), `CSQLite`, `Kept` app (macOS-only targets)
- ☑ App skeleton: agent app (`LSUIElement`), status item, empty panel toggled from the status item
- ☑ `scripts/build-app.sh` assembles a sandboxed, ad-hoc-signed `Kept.app`; `Makefile` (`build`, `test`, `app`, `run`)
- ☑ CI: macOS build + tests + app bundle; Linux core tests
- ☑ README, LICENSE (MIT), CLAUDE.md conventions

Notes:
- Also done early: the ⇧⌘V hotkey (KeyboardShortcuts 3.x) and the `Theme` tokens; a thin
  `SQLiteDatabase`/`SQLiteStatement` wrapper with smoke tests (M1 grows it into the store).
- Relaunching Kept shows the panel for now; M7 switches that to opening Settings.
- `Package.resolved` is not tracked: SwiftPM on Linux deletes it because the only
  dependency is macOS-only. KeyboardShortcuts is pinned with `from: "3.1.0"`.
- `build-app.sh` builds with `--build-system swiftbuild` and copies dependencies' resource
  bundles to `Contents/Resources`, where Swift Build's `Bundle.module` looks. (The native
  build system, still the default in Swift 6.3, looks only at the `.app` root and the
  build folder.) M6 should confirm the KeyboardShortcuts recorder shows its strings.

## M1 — History store (core)
- ☑ SQLite wrapper + schema + migrations (`clips`, `representations`)
- ☑ Content-addressed blob store for large payloads (images, RTF/HTML)
- ☑ Record with dedup (re-copy bumps to top, counts copies)
- ☑ Pins (never pruned, manual order), delete, clear unpinned
- ☑ Pruning: item limit (default 500 unpinned), per-item size cap, orphan blob cleanup

Notes:
- Payloads over 64 KB go to `blobs/<sha256>`; smaller ones stay inline in SQLite. The per-item
  cap (20 MB) is enforced by `ClipBuilder`, which drops the heaviest non-primary
  representations first. Pruning by total blob size (~500 MB, RESEARCH §10) isn't done yet.
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
- ☑ Skip Kept's own writes; pause capture; ignore next copy — core: `app.kept.Kept.own` marker and pause in `CapturePolicy`; app: own change counts, pause, one-shot ignore (menu/shortcut UI comes with M6/M7)
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
- ⏎ / ⌥⏎ / ⌘⏎ / ⌘1–9 / ⌥⌘1–9 copy and close for now; the footer says "Copy" until M4.
- `Kept --render-snapshots <dir>` renders 13 states × light/dark; CI uploads them as the
  `panel-snapshots` artifact.

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
- ◐ ⌘P pin/unpin, pinned section order, reorder pins (drag) — drag to reorder not yet
- ☑ ⌘⌫ delete, ⌥⌘⌫ clear unpinned (inline confirm bar, no modal)
- ☐ Right-click context menu on rows

## M6 — Settings
- ☐ Settings window (owned `NSWindow`, toolbar panes)
- ◐ General: launch at login (`SMAppService`), history size, paste directly vs copy only, always paste plain text, panel position — core `Preferences` done (M1)
- ◐ Shortcuts: open Kept, paste clipboard as plain text (no default), pause capture (no default) — names (`togglePanel`, `pastePlainText`, `togglePause`) declared and handled (A2); recorder UI not yet
- ◐ Privacy: pause, excluded apps (+/−, defaults), ignore Universal Clipboard, clear history — core `Preferences` and `HistoryStore.clearAll` done (M1)

## M7 — Menu bar & app identity
- ◐ Left-click toggles panel; right-click / ⌥-click menu (Pause, Clear history, Settings…, Quit) — M0 has toggle and Quit
- ☑ Custom template menu bar glyph; dimmed when paused — glyph + paused variant drawn (`MenuBarIcon`); follows `Preferences.isPaused` (A2)
- ☑ App icon — "the marked line" (`Resources/Icon/*.svg` → `scripts/make-icon.py` → `Resources/AppIcon.icns`)
- ☐ Reopen (launching again) opens Settings — escape hatch if the menu bar icon is hidden

## M8 — Images & files polish
- ☑ TIFF → PNG re-encode, thumbnails (`CGImageSource`), image size cap
- ☑ File icons and multi-file items; preview of images and files

## M9 — Onboarding, accessibility, release
- ◐ First-paste permission sheet with version-aware copy; pasteboard privacy check (`accessBehavior`) — A2 shows a version-aware copy-only hint with an "Allow Kept to paste…" button on the first paste without access; no sheet or `accessBehavior` check yet
- ◐ VoiceOver labels; Reduce Motion / Transparency / Increase Contrast — panel rows, filters and hints are labelled; no motion under Reduce Motion; stronger marker under Increase Contrast; needs a VoiceOver pass
- ☑ Snapshot renders of the panel for design review in CI (`Kept --render-snapshots <dir>`, artifact `panel-snapshots`)
- ☐ Release workflow (ad-hoc → signed → notarized when secrets exist), README screenshots

## Later (P2, only if it stays lean)
- Edit / rename clips (⌘E / ⌘R) — turns pins into snippets
- OCR text in images for search
- Paste stack / multi-paste
- Ignore by regex; App Intents

## Out of scope
Sync, iOS, AI, text transforms, pinboards/collections, themes beyond light/dark,
snippet expansion, plugins, telemetry.
