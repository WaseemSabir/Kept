# Contributing to Kept

Thanks for helping. Kept is a small, native macOS clipboard manager; the ground
rules are in [CLAUDE.md](CLAUDE.md) and apply to people and agents alike.

## Build and test

```sh
swift build && swift test   # Linux: KeptCore only (needs libsqlite3-dev); macOS: everything
make app                    # macOS: dist/Kept.app, ad-hoc signed
make run                    # macOS: builds and opens it
UNIVERSAL=1 make app        # macOS: arm64 + x86_64
make release                # macOS: universal zip, disk image and checksums in dist/
```

- On Linux, `Package.swift` leaves out the app targets, so only `KeptCore` and
  its tests build. AppKit and SwiftUI code only compiles on macOS (Xcode 26 or
  later).
- CI ([`ci.yml`](.github/workflows/ci.yml)) is the source of truth for the app:
  on macOS it builds, runs every test, renders the snapshots, builds
  `Kept.app`, checks it carries the shortcut recorder's strings, and launches
  it (reopening it must open Settings); on Linux it builds and tests
  `KeptCore`.
- Every local rebuild with an ad-hoc signature loses the Accessibility grant.
  Sign local builds with one persistent self-signed identity instead
  ([RELEASING.md](docs/RELEASING.md#local-builds-use-one-persistent-self-signed-identity)).

## Snapshots

The debug binary draws the panel, the copy-only hint and each Settings pane in
sample states, light and dark, for design review (macOS only):

```sh
swift build && .build/debug/Kept --render-snapshots /tmp/kept-snapshots
```

CI uploads the same images as the `panel-snapshots` artifact of each run.

## Where things go

- **Code layout:** [ARCHITECTURE.md](docs/ARCHITECTURE.md) — packages, key types,
  data flow, conventions. Logic that doesn't need AppKit belongs in `KeptCore`
  (Foundation-only) with Swift Testing tests; keep the app layer thin. One
  primary type per file.
- **Design:** [DESIGN.md](docs/DESIGN.md) — tokens, layout and principles; all UI
  follows it. Copy is sentence case and active voice, and buttons name the action.
- **Why things are the way they are:** [RESEARCH.md](docs/RESEARCH.md).
- **What's next:** [ROADMAP.md](docs/ROADMAP.md); update it when you finish
  something.
- **Releases:** [RELEASING.md](docs/RELEASING.md).

## Commits

- Small commits that each build and pass tests.
- Subject: imperative, sentence case, no trailing period, about 60 characters at
  most ("Fold search text with cached tables").
- Body, wrapped at 72 columns: what changed and why, not how.
- No build products (`.build/`, `dist/`), secrets or `.DS_Store`.
- No new third-party dependencies without a strong reason.
