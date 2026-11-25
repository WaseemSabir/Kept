# Kept's website

The product site for Kept: static HTML built with [Astro](https://astro.build).
Its design spec is the **Website** section of [`docs/DESIGN.md`](../docs/DESIGN.md);
every claim on it comes from [`README.md`](../README.md),
[`docs/DESIGN.md`](../docs/DESIGN.md) or [`docs/ROADMAP.md`](../docs/ROADMAP.md).

## Commands

Node 22 (Astro 7 needs 22.23.4 or later; `.nvmrc` says `22`):

```sh
cd site
npm ci
npm run dev       # http://localhost:4321, rebuilds as you edit
npm run build     # writes dist/
npm run preview   # serves dist/
npm run check     # astro check: TypeScript and Astro diagnostics
npm test          # the live panel's logic, with Node's own test runner
```

`npm test` runs `tests/**/*.test.ts` with `node --test`; Node 22 runs the
TypeScript as is (type stripping), so there is nothing to install. The tests
cover the panel's pure modules (below); `tests/node.d.ts` types the bits of
`node:test` and `node:assert` they use, so `npm run check` checks them too
without `@types/node`.

The build asks GitHub for the latest release and its disk image, and falls
back to the version in `Resources/Info.plist` and the releases page when it
can't (the repository is private, a rate limit, no network). It logs one line
saying which. Two environment variables are read at build time:

| Variable       | Use |
|----------------|-----|
| `GITHUB_TOKEN` | Sent to the GitHub API when set (higher rate limit, private repositories). |
| `SITE_URL`     | The site's address for canonical links; defaults to `https://kept.waseemsabir.com`. |

## Layout

```
astro.config.mjs        static output, /page → page.html, ../ allowed for imports
public/favicon.svg      a copy of Resources/Icon/AppIcon-32.svg
src/
  config.ts             names, URLs, the minimum macOS: shared facts
  assets.ts             the README's screenshots and the app icon, imported in place
  data/                 the copy, as data: clips (the panel's history), features,
                        privacy, shortcuts, faq, install, release (getRelease)
  lib/inline.ts         the inline convention used by the copy (below)
  styles/               tokens.css (DESIGN.md's tokens), base.css (type, column, links)
  layouts/Base.astro    the document: title, description, canonical, <slot name="head">
  components/           Header, Footer, Brand, Key, Inline, FactList, ShortcutTable,
                        DownloadButton, Screenshot
  components/panel/     the live panel, one small component per part
  scripts/panel/        the script that makes it work (below)
  pages/                index, shortcuts, privacy, 404
tests/panel/            node:test tests for src/scripts/panel
```

Rules of thumb:

- **One copy of every image.** Screenshots and the icon are imported from
  `docs/images` and `Resources/Icon` through `astro:assets`; update them there.
- **No third parties.** No fonts, scripts, analytics or cookies; the system
  font only. Dependencies are `astro` (and, for `npm run check`,
  `@astrojs/check` and `typescript`).
- **Components don't set their own outer margins.** The page around them
  owns spacing (`.section` in `base.css`, wrappers in the pages), so section
  and component rules never fight.

## Copy: the inline convention

Strings in `src/data` are plain text with a tiny Markdown subset, so the same
strings can be rendered as HTML, plain text or Markdown
(`parseInline`, `toPlainText`, `toMarkdown` in `src/lib/inline.ts`):

| Write          | For                           | Renders as |
|----------------|-------------------------------|------------|
| `` `code` ``   | commands, paths, values       | `<code>` |
| `**strong**`   | names of buttons and settings | `<strong>` |
| `[text](url)`  | a link                        | `<a>` |
| `{⌘P}`         | a shortcut                    | a key cap (`<kbd>`) |

## The live panel

`src/components/panel/` rebuilds the app's panel at its own sizes (720 × 460,
52 px search bar, 34 px rows, 324 px list, 30 px footer) from
`src/data/clips.ts`, the same history as `SampleHistory.swift`. Without
JavaScript it is a still, made of real DOM, in the state the README shows
(the image selected). `src/scripts/panel/` makes it work; DESIGN.md › Website
› The live panel is the spec.

### The script

Vanilla TypeScript, no dependencies, loaded by a `<script>` in
`LivePanel.astro`, which Astro bundles into one external module
(`/_astro/LivePanel…js`, about 22 kB, 8 kB gzipped, the clip history
included). It imports `src/data/clips.ts`, so the page and the script share
one copy of the history. Logic is kept apart from the DOM so it can be
tested:

| Module | What it is | Port of |
|--------|------------|---------|
| `fold.ts` | Text folded for matching: case, diacritics, width | `SearchKey` |
| `search.ts` | What the list shows for a query and a filter, best first | `ClipSearch`, `ClipFilter` |
| `highlight.ts` | Where the query matches a row, and the "…" excerpt | `MatchHighlighter`, `ClipSummary` |
| `history.ts` | Pin, unpin, delete; the section break; which row stays selected | `HistoryStore`, `PanelViewModel` |
| `keys.ts` | Keys to commands | `PanelKeyRouter` |
| `wording.ts` | Empty states, footer hints, what's announced, what a paste puts on the line | `PanelViewModel+Display`, `PanelFooter`, `PasteHintCopy` |
| `view.ts` | Brings the server-rendered rows, previews, footer and empty state in line with the state (DOM) | |
| `stage.ts` | The panel closing and opening, the copy-only hint, the paste line (DOM) | |
| `main.ts` | The state and the events: keys, clicks, taps, ⇧⌘V | |

Rules it keeps:

- **Progressive.** It sets `<html data-scripted>` once it has taken over;
  until then the hint under the panel is hidden and the caret doesn't blink.
- **Focus.** Nothing is focused on load and Tab is never taken. Keys act only
  while focus is in the panel, except ⇧⌘V, which puts the keyboard in the
  search field from anywhere on the page (and, while the copy-only hint
  shows, ⌘V outside a text field puts the copied clip on the paste line). A
  click in the panel focuses the field; a tap doesn't, so a phone's keyboard
  stays down. `preventDefault` only for keys it handles.
- **CSP-ready.** No inline scripts, handlers or `style` attributes; state is
  shown with attributes and classes, and what's typed reaches the page only
  as text nodes. The two color swatches are SVG `fill`s for the same reason.
- **Never the real clipboard.** It neither reads nor writes it; a "copy"
  lives in the script.

### Hooks

| Hook | What |
|------|------|
| `html[data-scripted]` | Set by the script: shows the hint under the panel and starts the paste line's caret. |
| `[data-panel]` | The window; `data-filter`, `data-selected` hold the state, `data-empty` ("list" or "panel") places the empty state; `.is-closing`, `.is-closed`, `.is-opening` for a paste. |
| `[data-panel-search]` | The search field: a combobox, `aria-activedescendant` names the selected row. |
| `[data-filter]` | Filter buttons, `aria-pressed`. |
| `#panel-list`, `#clip-<id>` | The listbox (`tabindex="-1"`: the combobox keeps the keyboard) and its rows (`aria-selected`, `data-pinned`, `data-section-start`, `.number`, `.age`, `.text`). |
| `[data-preview="<id>"]` | One preview per clip; all but the selected one are `hidden`. `[data-fact]` names each fact's value. |
| `[data-panel-empty]` | The empty state's `[data-empty-title]` and `[data-empty-hint]`. |
| `[data-panel-footer]`, `[data-hint]` | Key hints, buttons out of the Tab order; `[data-hint-label]` holds each label ("Pin" / "Unpin"). |
| `[data-panel-hud]` | The copy-only hint, "Copied. Press ⌘V to paste." |
| `[data-panel-hint]`, `[data-panel-reset]` | The line under the panel (keys or touch wording, by `hover`) and its Reset button. |
| `[data-panel-status]` | A polite live region, outside the panel so it still speaks while the panel is closed. |
| `[data-paste-line]`, `[data-paste-text]` | The line a paste lands on; the placeholder hides once `data-paste-text` has content. `template[data-paste-image]` is the picture an image pastes as. |
