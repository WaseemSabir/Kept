# Kept — working notes for contributors and agents

Kept is an open-source, native macOS clipboard manager (Swift 6, AppKit +
SwiftUI, macOS 14+). Read these before changing code:

- `docs/ROADMAP.md` — what's done and what's next (update it when you finish something)
- `docs/ARCHITECTURE.md` — package layout, key types, data flow, conventions
- `docs/DESIGN.md` — tokens, layout, principles; all UI must follow it

## Commands

```sh
swift build                    # Linux: builds KeptCore only; macOS: everything
swift test                     # Linux: KeptCore tests; macOS: all tests
make app                       # macOS: builds dist/Kept.app (ad-hoc signed)
make run                       # macOS: builds and opens Kept.app
```

On Linux the app targets are excluded by `#if os(macOS)` in `Package.swift`, so
`swift build && swift test` exercise `KeptCore` only. AppKit/SwiftUI code can
only be compiled on macOS — CI (`.github/workflows/ci.yml`) is the source of
truth for the app target.

## Rules

- Logic that doesn't need AppKit belongs in `KeptCore`, with Swift Testing
  tests (`import Testing`). Keep the app layer thin.
- `KeptCore` must stay Foundation-only (no AppKit, CryptoKit, SwiftUI, Combine).
  It must build and pass tests on Linux.
- Swift 6 strict concurrency; UI types and stores are `@MainActor`.
- No new third-party dependencies beyond `KeyboardShortcuts` without a strong reason.
- No SwiftPM `resources:` in the app target; use `Resources/` + `Bundle.main`.
- One primary type per file, folders as in ARCHITECTURE.md.
- UI copy: sentence case, active voice, buttons name the action.
- Never commit secrets, build products (`.build/`, `dist/`) or `.DS_Store`.
