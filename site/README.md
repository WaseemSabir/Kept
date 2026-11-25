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
npm test          # the panel's logic, the generated files, check:dist itself
npm run check:dist  # checks the built dist/ (run after build; CI does)
npm run images    # remakes the icons and the social card in public/ (a Mac with Chrome)
```

`npm test` runs `tests/**/*.test.ts` with `node --test`; Node 22 runs the
TypeScript as is (type stripping), so there is nothing to install. The tests
cover the panel's pure modules (below), what the site generates for search
engines and assistants (`tests/site/`) and `scripts/check-dist.mjs`;
`tests/node.d.ts` types the bits of `node:test` and `node:assert` they use, so
`npm run check` checks them too without `@types/node`. Modules the tests
import name their imports with `.ts`, as Node needs.

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
astro.config.mjs        static output, /page → page.html, no inline stylesheets, ../ allowed
vercel.json             headers (CSP), clean URLs, /download, caching, when to deploy
public/                 favicon.svg, favicon.ico, icons, og.png: made by `npm run images`
scripts/
  make-images.mjs       the icons and the social card (below)
  check-dist.mjs        npm run check:dist (below)
  vercel-ignore.sh      Vercel's ignored build step (below)
src/
  config.ts             names, URLs, the minimum macOS, colors: shared facts
  assets.ts             the README's screenshots and the app icon, imported in place
  data/                 the copy, as data: pages (titles, descriptions, page prose),
                        clips (the panel's history), features, privacy, shortcuts,
                        faq, install, screenshots, release (getRelease)
  lib/inline.ts         the inline convention used by the copy (below)
  lib/                  structured-data, documents (Markdown twins, llms files),
                        markdown, crawlers (robots.txt, sitemap), images, responses
  styles/               tokens.css (DESIGN.md's tokens), base.css (type, column, links)
  layouts/Base.astro    the document and its whole <head>, from the page's entry in data/pages.ts
  components/           Header, Footer, Brand, Key, Inline, FactList, ShortcutTable,
                        DownloadButton, Screenshot
  components/panel/     the live panel, one small component per part
  scripts/panel/        the script that makes it work (below)
  pages/                index, shortcuts, privacy, 404; *.ts endpoints for robots.txt,
                        sitemap.xml, llms.txt, llms-full.txt, the Markdown twins, the manifest
tests/panel/            node:test tests for src/scripts/panel
tests/site/             what the site tells search engines and assistants
tests/check-dist.test.ts  check:dist on a made-up site, whole and broken
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
- **No inline style or script, ever.** The Content-Security-Policy
  (`vercel.json`) is `style-src 'self'` and `script-src 'self'`, so a
  `<style>` block, a `style=""` attribute or an inline `<script>` simply
  doesn't apply in production. Astro is set to write every stylesheet as a
  file; per-element values go in data attributes the stylesheet reads
  (`Screenshot.astro`'s `data-window`, `data-inset`), and scripts set state
  with attributes and classes. `npm run check:dist` fails on any of them.
- **One copy of every string.** A page's title, description and prose live
  in `src/data/` (`pages.ts` for what is the page's own), and the HTML, the
  Markdown twins, llms-full.txt and the structured data are all made from
  them.

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

## Search engines and assistants

Every page's `<head>` comes from `Base.astro` and the page's entry in
`src/data/pages.ts`: the title (60 characters at most) and description (155),
the canonical address (`SITE_URL`'s origin, no trailing slash but the home
page's), `og:*` and `twitter:card` for link previews with `og.png`,
`theme-color` (the `page` token), the icons, the manifest, a
`<link rel="alternate" type="text/markdown">` to the page's Markdown twin, and
its structured data. The 404 is `noindex` and has none of the last three.

| File | What it is | Made by |
|------|------------|---------|
| `/robots.txt` | Everyone may read everything; the AI crawlers and assistants' fetchers are named as welcome; points to the sitemap | `src/lib/crawlers.ts` |
| `/sitemap.xml` | The indexable pages (`indexedPages`), no `lastmod` (the build can't know it) | `src/lib/crawlers.ts` |
| `/llms.txt` | [llmstxt.org](https://llmstxt.org): what Kept is, key facts, links to the twins and the project | `src/lib/documents.ts` |
| `/llms-full.txt` | The whole site as one Markdown document | `src/lib/documents.ts` |
| `/index.html.md`, `/shortcuts.md`, `/privacy.md` | Each page as Markdown (llmstxt.org's naming: the address plus `.md`) | `src/lib/documents.ts` |
| `/manifest.webmanifest` | Name, icons, colors; `display: browser` | `src/pages/manifest.webmanifest.ts` |
| JSON-LD in each page | One `@graph`: on the home page `WebSite`, `SoftwareApplication` (version and download from `getRelease()`), `SoftwareSourceCode` and `FAQPage` (from `faq.ts`); elsewhere `WebPage` and `BreadcrumbList` | `src/lib/structured-data.ts` |

All of it is built from the same data modules as the pages, so a change to
the copy reaches every one of them. The twins repeat the pages' section
headings; `check:dist` fails if a twin has a heading its page doesn't. The
structured data claims only what the README says: no ratings, reviews or
counts. The twins and llms files are sent with `X-Robots-Tag: noindex,
follow`: search engines should list the HTML pages, which say the same.

To add a page: give it an entry in `pages.ts` (and `indexedPages`), pass it
to `Base`, and, if it's indexable, add its twin to `documents.ts` and an
endpoint in `src/pages/`. The sitemap, llms.txt and the checks follow.

## Images

`public/` holds the icons and the social card. They're made from the app
icon's SVGs (`Resources/Icon/`) and the built home page, by headless Chrome
on a Mac, and committed; CI never makes them.

```sh
npm run build && npm run images    # CHROME_PATH=… if Chrome isn't in /Applications
```

| File | What |
|------|------|
| `favicon.svg` | A copy of `AppIcon-32.svg`, the icon hinted for 32 px |
| `favicon.ico` | `AppIcon-16.svg` and `AppIcon-32.svg` at 16 and 32 px, PNGs in an ICO (crawlers ask for it) |
| `icon-192.png`, `icon-512.png` | `AppIcon.svg` as is, the macOS margin included |
| `apple-touch-icon.png` | 180 px, full bleed: the graphite to every edge, since iOS rounds the corners itself |
| `icon-maskable-512.png` | Full bleed, the drawing inside the central circle every mask keeps |
| `og.png` | The social card, 1200 × 630 |

The social card isn't a template: the script serves `dist/`, opens the home
page without its script (so the panel is the server-rendered still, the
image selected), and rearranges the page's own brand, headline and panel
into the card, so it always matches the site. Chrome draws the system font.
Look at `og.png` after remaking it.

## `npm run check:dist`

Checks the built `dist/` in a few dozen milliseconds, Node built-ins only,
and fails with the file and the reason:

- every internal `href`, `src` and `srcset` resolves to a file the way the
  host serves it (`/shortcuts` is `shortcuts.html`), every `#fragment` to an
  element id; no link to an address that only redirects (`/x.html`, `/x/`);
- each page has one `<h1>`, a unique `<title>` (≤ 60) and description
  (≤ 155), and, unless it's `noindex`, a canonical on the site's origin that
  names the page itself, a Markdown twin and structured data;
- the sitemap lists exactly the indexable pages; every JSON-LD block parses
  and has `@context`, and its addresses on the site exist;
- robots.txt, the sitemap, llms.txt, llms-full.txt, the twins, the manifest,
  the icons and `og.png` (1200 × 630, read from the PNG) are there and well
  formed;
- nothing the CSP would block: no `<style>`, `style=""`, `on…=""`,
  executable inline `<script>` or `javascript:` URL;
- nothing loaded from another origin (scripts, stylesheets, images, media,
  fonts and other `url()`s in CSS);
- `vercel.json` parses, sets a CSP without `unsafe-inline`, and its
  `ignoreCommand` script exists and is executable.

It checks against `SITE_URL`, or the production address in `src/config.ts`,
the same origin the build used.

## Hosting: Vercel

Vercel builds the site through its Git integration. The project's Root
Directory is `site`, so `vercel.json` lives here and commands run here; the
rest of the repository is still checked out, which the build needs
(`../docs/images`, `../Resources`). The production branch is `master`; pull
requests get previews.

`vercel.json` sets:

- **Headers for every path:** a `Content-Security-Policy` that allows only
  the site's own scripts, stylesheets, images, manifest and connections
  (`default-src 'none'`; no inline code; `frame-ancestors 'none'`), plus
  `X-Content-Type-Options`, `Referrer-Policy`, `X-Frame-Options`,
  `Cross-Origin-Opener-Policy` and a `Permissions-Policy` that turns off
  every feature the site doesn't use. Anything new that the page loads must
  fit the policy: no third parties, no inline code.
- **Content types:** `.md` as `text/markdown; charset=utf-8` and `.txt` as
  `text/plain; charset=utf-8` (by extension alone they'd have no charset,
  and the copy has ⇧⌘⏎ and curly quotes); the twins and llms files also get
  `X-Robots-Tag: noindex, follow`.
- **`cleanUrls` and `trailingSlash: false`:** `/shortcuts`, never
  `/shortcuts.html` or `/shortcuts/` (those redirect).
- **Caching:** `/_astro/*` (hashed names) for a year, `immutable`;
  everything else is revalidated.
- **`/download`:** a temporary redirect to the latest release on GitHub, one
  address to share that never goes stale.

### When it deploys

`ignoreCommand` runs `scripts/vercel-ignore.sh` (Vercel's "Ignored Build
Step": exit 0 skips, 1 builds) as `sh scripts/vercel-ignore.sh || exit 1`,
so a missing script or any unexpected exit builds. It prints one line with
its decision and why, and builds when:

- the branch has no previous deployment (`VERCEL_GIT_PREVIOUS_SHA` unset);
- the previous deployment is of this same commit: a redeploy, or a deploy
  hook;
- the previous commit isn't in Vercel's shallow clone;
- `site/`, `docs/images`, `Resources/Icon` or `Resources/Info.plist`
  changed since the previous deployment.

Otherwise (a push that only touches the app or other docs) it skips. The
download button and version come from GitHub's latest release at build
time, so after publishing a release, redeploy (or run a deploy hook): the
same commit always builds.
