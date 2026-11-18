# Kept — Roadmap

Living checklist. Each milestone is built, tested (Linux unit tests for
`KeptCore`, macOS CI build for the app) and committed to `master` before the
next one starts. Scope comes from [RESEARCH.md](RESEARCH.md); look and feel
from [DESIGN.md](DESIGN.md); structure from [ARCHITECTURE.md](ARCHITECTURE.md).

Status: ☐ todo · ◐ in progress · ☑ done

## M0 — Foundation
- ☐ Swift package: `KeptCore` (Foundation-only, Linux-testable), `CSQLite`, `Kept` app (macOS-only targets)
- ☐ App skeleton: agent app (`LSUIElement`), status item, empty panel toggled from the status item
- ☐ `scripts/build-app.sh` assembles a sandboxed, ad-hoc-signed `Kept.app`; `Makefile` (`build`, `test`, `app`, `run`)
- ☐ CI: macOS build + tests + app bundle; Linux core tests
- ☐ README, LICENSE (MIT), CLAUDE.md conventions

## M1 — History store (core)
- ☐ SQLite wrapper + schema + migrations (`clips`, `representations`)
- ☐ Content-addressed blob store for large payloads (images, RTF/HTML)
- ☐ Record with dedup (re-copy bumps to top, counts copies)
- ☐ Pins (never pruned, manual order), delete, clear unpinned
- ☐ Pruning: item limit (default 500 unpinned), per-item size cap, orphan blob cleanup

## M2 — Clipboard capture
- ☐ `PasteboardSnapshot` + `CapturePolicy` (core): nspasteboard.org markers, legacy password types, excluded apps, whitespace-only, size caps, skipped heavy types
- ☐ Primary kind detection: text / rich text / link / image / file(s) / color
- ☐ `PasteboardMonitor` (app): `changeCount` polling with tolerance, source app (`org.nspasteboard.source` → frontmost app)
- ☐ Skip Kept's own writes; pause capture; ignore next copy
- ☐ Default excluded apps (Passwords, Keychain Access, 1Password, Bitwarden, KeePassXC)

## M3 — The panel
- ☐ Non-activating floating `NSPanel` hosting SwiftUI; centered on the active screen
- ☐ Global hotkey ⇧⌘V (KeyboardShortcuts) toggles the panel
- ☐ Search field (always focused), live filtering, fuzzy-ish matching (core `ClipSearch`)
- ☐ List with quick-paste numbers, pinned section, kind-aware rows (swatch, thumbnail, host/path, mono for code)
- ☐ Preview pane with facts (source, copied, size)
- ☐ Footer with shortcut hints; empty states
- ☐ Design tokens (`Theme`) and highlighter selection
- ☐ Keyboard: ↑/↓ ⌃N/⌃P, ⌘↑/⌘↓, PgUp/PgDn, Esc (clear → close), ⌃U, Tab/⇧Tab type filter

## M4 — Paste
- ☐ Write a clip back to the pasteboard (all representations / plain text only)
- ☐ Synthesize ⌘V into the previous app (layout-aware key code), skip own write in monitor
- ☐ ⏎ paste · ⌥⏎ plain · ⌘⏎ copy only · ⌘1–9 · ⌥⌘1–9
- ☐ Permission: `CGPreflightPostEventAccess` / request on first paste; copy-only fallback with hint

## M5 — Pins & cleanup
- ☐ ⌘P pin/unpin, pinned section order, reorder pins (drag)
- ☐ ⌘⌫ delete, ⌥⌘⌫ clear unpinned (confirm)
- ☐ Right-click context menu on rows

## M6 — Settings
- ☐ Settings window (owned `NSWindow`, toolbar panes)
- ☐ General: launch at login (`SMAppService`), history size, paste directly vs copy only, always paste plain text, panel position
- ☐ Shortcuts: open Kept, paste clipboard as plain text (no default), pause capture (no default)
- ☐ Privacy: pause, excluded apps (+/−, defaults), ignore Universal Clipboard, clear history

## M7 — Menu bar & app identity
- ☐ Left-click toggles panel; right-click / ⌥-click menu (Pause, Clear history, Settings…, Quit)
- ☐ Custom template menu bar glyph; dimmed when paused
- ☐ App icon (`.icns` via `iconutil`)
- ☐ Reopen (launching again) opens Settings — escape hatch if the menu bar icon is hidden

## M8 — Images & files polish
- ☐ TIFF → PNG re-encode, thumbnails (`CGImageSource`), image size cap
- ☐ File icons and multi-file items; preview of images and files

## M9 — Onboarding, accessibility, release
- ☐ First-paste permission sheet with version-aware copy; pasteboard privacy check (`accessBehavior`)
- ☐ VoiceOver labels; Reduce Motion / Transparency / Increase Contrast
- ☐ Snapshot renders of the panel for design review in CI
- ☐ Release workflow (ad-hoc → signed → notarized when secrets exist), README screenshots

## Later (P2, only if it stays lean)
- Edit / rename clips (⌘E / ⌘R) — turns pins into snippets
- OCR text in images for search
- Paste stack / multi-paste
- Ignore by regex; App Intents

## Out of scope
Sync, iOS, AI, text transforms, pinboards/collections, themes beyond light/dark,
snippet expansion, plugins, telemetry.
