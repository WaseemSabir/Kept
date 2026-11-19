# Kept

A small, keyboard-first clipboard history for the Mac. Native (Swift,
AppKit and SwiftUI), private, and open source.

> **Early days.** Kept hasn't had a release yet. History, search, paste,
> pins and Settings work; onboarding polish and a first release come next.
> See the [roadmap](docs/ROADMAP.md) for what's done and what's next.

## What it will do

- Keep what you copy — text, rich text, links, images, files and colors.
- Press ⇧⌘V for a Spotlight-style panel: type to search, ⏎ to paste into the
  app you were just using, ⌘1–⌘9 for the first nine items.
- Pin the things you reuse; pins are never pruned.
- Stay out of your secrets: skip password managers and anything marked
  concealed or transient, and let you exclude apps.
- Stay on your Mac: sandboxed, no sync, no accounts, no telemetry.

## Requirements

- macOS 14 Sonoma or later
- To build: Xcode 26 or later (Swift 6.2+)

## Install

Download `Kept-<version>.dmg` from
[Releases](https://github.com/WaseemSabir/Kept/releases), open it and drag Kept
to Applications.

- If a release isn't notarized, macOS blocks the first launch. On macOS 15 and
  later, open Kept once, then click **Open Anyway** in System Settings › Privacy
  & Security. On macOS 14, Control-click Kept and choose **Open**.
- Pasting needs Accessibility access. Releases without a Developer ID signature
  lose it with every update: remove Kept from System Settings › Privacy &
  Security › Accessibility and add it again.

[RELEASING.md](docs/RELEASING.md) has the details.

## Build from source

```sh
git clone https://github.com/WaseemSabir/Kept.git
cd Kept
make app    # builds and ad-hoc signs dist/Kept.app
make run    # builds and opens it
```

Kept lives in the menu bar and has no Dock icon. Click its icon or press
⇧⌘V to open the panel; right-click the icon for the menu. Open Kept again
(from Finder or Spotlight) for Settings — the way back in if macOS hides the
menu bar icon.

- `UNIVERSAL=1 make app` builds for Apple silicon and Intel.
- `SIGN_IDENTITY="Developer ID Application: …" make app` signs with your
  certificate instead of an ad-hoc signature.
- `make test` runs the tests. The core library (`KeptCore`) also builds and
  tests on Linux with `swift build && swift test`.

### Accessibility access on local builds

Pasting into other apps needs Accessibility access. macOS ties that grant to
the app's code signature, and an ad-hoc signature changes with every build:
after a rebuild the grant silently stops working, even though System Settings
still shows it as on. Reset it and grant it again:

```sh
tccutil reset Accessibility app.kept.Kept
```

To avoid this, sign local builds with one persistent certificate (for
example a self-signed one) through `SIGN_IDENTITY`.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [CLAUDE.md](CLAUDE.md) for the
ground rules, then
[ARCHITECTURE.md](docs/ARCHITECTURE.md), [DESIGN.md](docs/DESIGN.md) and
[RESEARCH.md](docs/RESEARCH.md).

## License

MIT. See [LICENSE](LICENSE).
