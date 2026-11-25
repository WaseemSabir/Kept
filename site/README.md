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
```

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
  pages/                index, shortcuts, privacy, 404
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
`src/data/clips.ts`, the same history as `SampleHistory.swift`. This step
ships no JavaScript: the panel is a still, made of real DOM, in the state the
README shows (the image selected). Hooks for a script:

| Hook | What |
|------|------|
| `html[data-scripted]` | Set it when the script runs: shows the hint under the panel and starts the paste line's caret. |
| `[data-panel]` | The window; `data-filter`, `data-selected` hold the state; add `.is-opening` for the 120 ms open motion. |
| `[data-panel-search]` | The search field: a combobox, `aria-activedescendant` names the selected row. |
| `[data-filter]` | Filter buttons, `aria-pressed`. |
| `#panel-list`, `#clip-<id>` | The listbox and its rows (`aria-selected`, `data-pinned`, `data-section-start`, `.number`). |
| `[data-preview="<id>"]` | One preview per clip; all but the selected one are `hidden`. |
| `[data-panel-footer]`, `[data-hint]` | Key hints; `[data-hint-label]` holds each label ("Pin" / "Unpin"). |
| `[data-panel-status]` | A polite live region for announcements. |
| `[data-paste-line]`, `[data-paste-text]` | The line a paste lands on; the placeholder hides once `data-paste-text` has text. |
