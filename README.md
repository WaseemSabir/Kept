# Kept

A keyboard-first clipboard history for the Mac. Native, private, and open source.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

<p align="center">
  <img src="docs/images/panel-light.png" width="720" alt="The Kept panel in light mode: a search field and type filters on top, a list of recent clips (two pinned at the top) with the selected image marked by a yellow highlighter, and a preview of that image with where it came from and when.">
</p>

> **Early days.** Kept is at 0.1, its first version. History, search,
> pasting, pins and Settings work, but few people have used it yet: expect
> rough edges, and please [report them](https://github.com/WaseemSabir/Kept/issues).
> The [roadmap](docs/ROADMAP.md) says what's done and what's next.

## Features

- **Keeps what you copy:** text, rich text, links, images, files, and colors.
- **Fast from the keyboard:** `⇧⌘V` opens the panel over your active app. Type
  to search, press `⏎` to paste, or `⌘1`–`⌘9` for the first nine clips.
- **Flexible pasting:** `⌥⏎` pastes as plain text; `⌘⏎` copies without pasting.
- **Pins & snippets:** Pin clips you reuse (`⌘P`) so they stay on top and are
  never pruned. Rename a clip (`⌘R`) or edit its text (`⌘E`) — search matches
  clip names too.
- **Content-aware rows:** Colors show a swatch, images a thumbnail, files an
  icon, links their host, and code in monospace. Search highlights matched words.
- **Native Mac app:** Built with Swift, AppKit, and SwiftUI in light and dark
  mode, respecting VoiceOver, Reduce Motion, Reduce Transparency, and Increase
  Contrast. Lives in the menu bar or runs completely out of sight.

<p align="center">
  <img src="docs/images/panel-dark.png" width="720" alt="The Kept panel in dark mode while searching for “pasteboard”: two matching clips, the matched word set in bold, and the selected code clip previewed in full.">
</p>

## Keyboard shortcuts

**Global** (customizable in Settings › Shortcuts):

| Keys | Action |
|---|---|
| `⇧⌘V` | Open or close Kept |
| *(none by default)* | Paste the clipboard as plain text |
| *(none by default)* | Pause or resume capture |

**In the panel** (the search field always has focus):

| Keys | Action |
|---|---|
| *type* | Search |
| `↑` `↓` · `⌃P` `⌃N` | Move selection |
| `⌘↑` `⌘↓` · `Home` `End` · `PgUp` `PgDn` | First, last, or page up/down |
| `⏎` · `⌥⏎` · `⌘⏎` | Paste · paste as plain text · copy only |
| `⌘1`–`⌘9` · `⌥⌘1`–`⌥⌘9` | Paste clip 1–9 · as plain text |
| `⌘P` | Pin or unpin |
| `⌘R` | Rename selected clip (`⏎` saves, `Esc` cancels) |
| `⌘E` | Edit selected clip's text (`⌘S` saves, `Esc` cancels) |
| `⌥⌘↑` `⌥⌘↓` | Reorder pinned clip (or drag it) |
| `⌘⌫` | Delete selected clip (when search is empty) |
| `⌥⌘⌫`, then `⌥⌘⌫` | Clear all unpinned clips |
| `Tab` / `⇧Tab` | Next or previous type filter |
| `⌃U` · `Esc` | Clear search · clear search, then close |
| `⌘,` | Open Settings |

With **Always paste as plain text** enabled, `⏎` and `⌥⏎` swap. Right-click any
clip for the same actions.

## Install

Kept needs macOS 14 Sonoma or later.

1. Download `Kept-<version>.dmg` from the
   [latest release](https://github.com/WaseemSabir/Kept/releases/latest), open
   it and drag Kept to Applications.
2. Open Kept. A short welcome tells you where it is: in the menu bar, and on
   ⇧⌘V.

**If macOS says "“Kept” Not Opened"**: releases aren't notarized by Apple
yet, so macOS stops the first launch. On macOS 15 and later, click **Done**,
then **Open Anyway** in System Settings › Privacy & Security (under Security).
On macOS 14, Control-click Kept and choose **Open**. Or run
`xattr -dr com.apple.quarantine /Applications/Kept.app` in Terminal.

**Pasting for you needs your permission.** Kept pastes by pressing ⌘V in the
app you were using, which macOS allows only once you turn Kept on in System
Settings › Privacy & Security (under Accessibility up to macOS 26). Kept asks
the first time you paste; until then it copies the clip and you press ⌘V
yourself. Releases without a Developer ID signature lose this permission
with each update: remove Kept from the list and add it again.
[RELEASING.md](docs/RELEASING.md) has the details.

## Privacy & security

- **Stays on your Mac.** The history lives in Kept's sandbox container
  (`~/Library/Containers/app.kept.Kept`), readable only by you. Kept has no
  network access, no accounts, no sync and no telemetry.
- **Skips secrets.** Copies that apps mark as concealed, transient or
  auto-generated ([nspasteboard.org](http://nspasteboard.org) markers) are
  never saved, and neither is anything copied in Passwords, Keychain Access,
  1Password, Bitwarden or KeePassXC.
- **You decide.** Add or remove excluded apps in Settings › Privacy, pause
  capture from the menu bar menu (or a shortcut), choose "Ignore next copy"
  before copying something sensitive, skip copies from your other devices,
  and clear the history any time.
- **Forgets on a schedule, if you like.** Settings › Privacy › "Forget
  unpinned clips" deletes clips you haven't copied or pasted for a day, a
  week or a month. Pinned clips always stay.
- **macOS 15.4+ clipboard access:** If macOS is set to ask or deny clipboard
  reads for Kept, Kept detects this and shows where to allow it.

To report a privacy or security issue, please see [SECURITY.md](SECURITY.md).

<p align="center">
  <img src="docs/images/settings.png" width="560" alt="Kept's Settings window on the General pane: open at login, show Kept in the menu bar, history size, pasting options and where the panel opens.">
</p>

## Build from source

```sh
git clone https://github.com/WaseemSabir/Kept.git
cd Kept
make app    # builds and ad-hoc signs dist/Kept.app (macOS, Xcode 26 or later)
make run    # builds and opens it
make test   # every test, on macOS
```

On Linux, `swift build && swift test` builds and tests the core library
(`KeptCore`: storage, capture rules, search; needs `libsqlite3-dev`). The app
itself builds only on macOS.

Local builds are ad-hoc signed, so macOS forgets the paste permission after
each rebuild. Sign them with one persistent certificate through
`SIGN_IDENTITY` to keep it ([how](docs/RELEASING.md#local-builds-use-one-persistent-self-signed-identity)),
or reset it with `tccutil reset Accessibility app.kept.Kept`.

## Contributing

Contributions are welcome! Read [CONTRIBUTING.md](CONTRIBUTING.md) and
[CLAUDE.md](CLAUDE.md) for the ground rules, then check
[ARCHITECTURE.md](docs/ARCHITECTURE.md), [DESIGN.md](docs/DESIGN.md), and
[RELEASING.md](docs/RELEASING.md). All participation is governed by the
[Code of Conduct](CODE_OF_CONDUCT.md).

## License

MIT. See [LICENSE](LICENSE).
