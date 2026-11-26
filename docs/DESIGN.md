# Kept — Design

This is the design specification for Kept: its token system, layout,
interactions, and visual principles. Anything visual in the app should trace
back to a decision here.

## Brief

- **Subject:** a clipboard history for the Mac.
- **Audience:** people who copy all day — developers, writers, designers,
  support folks.
- **Primary job:** find something you copied earlier and put it back where
  you're typing, in under two seconds, without touching the mouse.
- **Vernacular:** copy, paste, keep, pin, mark, snippet. The word "Kept" is
  about holding on to the things you meant to hold on to.

## Token system

### Color

The panel sits on native vibrancy (`NSVisualEffectView`, `.popover`/`.hudWindow`
material), so most surfaces are the system's own material and semantic colors.
There is exactly one brand color.

| Token        | Light                         | Dark                          | Role |
|--------------|-------------------------------|-------------------------------|------|
| `ink`        | `labelColor`                  | `labelColor`                  | Primary text |
| `inkMuted`   | `secondaryLabelColor`         | `secondaryLabelColor`         | Metadata, hints |
| `inkFaint`   | `tertiaryLabelColor`          | `tertiaryLabelColor`          | Quick-paste numbers, placeholders |
| `hairline`   | `separatorColor`              | `separatorColor`              | Pane divider, footer rule |
| `marker`     | `#FFD84D` @ 60% under text    | `#F2CC47` @ 94% under text    | Selection highlight, active filter |
| `markedInk`  | `labelColor`                  | `#1C1C1E`                     | Text on the marker (the selected row's title) |
| `markedInkMuted` | black @ 62%               | `#1C1C1E` @ 75%               | Muted text on the marker (a link's path, file names) |
| `markerInk`  | `#6E5400`                     | `#1C1C1E`                     | Active filter text, on the marker |
| `markerNotch`| `#F5C400`                     | `#E8B73A`                     | Pin notch (full strength, so a 3 pt mark reads) |

With Increase Contrast on, `marker` rises to 95% (light) / `#FFD84D` at
full strength (dark) and `markerInk` darkens to `#5C4600` in light mode.

Dark mode marks a line the way a real highlighter (and the app icon's
marked line) does: near-opaque yellow under dark ink. A translucent yellow
under white text can't get brighter than a dull olive before the text
drops under 4.5:1. Every marked text clears 4.5:1: in light mode label
text ≈12:1, muted ≈5.6:1, the filter's `#6E5400` ≈5.5:1; in dark mode
`#1C1C1E` ≈9.8:1 and its 75% ≈5.5:1. Only what sits on the marker changes
color; the age, icons, swatch and thumbnail beside it don't.

`marker` is a highlighter, not a button color: it is drawn as a soft,
rounded swipe *behind* the selected row's text, the way you'd mark a line on
paper. It never appears as a solid control fill.

### Type

One family — the system font (SF Pro) — because this is a native Mac utility
and should feel at home next to Spotlight and Finder. Personality comes from
*what* is set in which style, not from a novelty face.

| Style        | Spec                                   | Use |
|--------------|----------------------------------------|-----|
| `searchField`| 20pt, regular, ink                     | Search input — big, like Spotlight |
| `rowTitle`   | 13pt, regular, ink, single line        | Clip summary in the list |
| `rowMeta`    | 11pt, regular, inkMuted                | Source app, age |
| `index`      | 11pt, medium, monospaced digits, inkFaint | Quick-paste numbers 1–9 |
| `preview`    | 13pt regular (prose) / 12pt SF Mono (code, paths, JSON) | Preview pane |
| `footerKey`  | 11pt, medium, inkMuted; key caps in 10pt | Shortcut hints |

Content-aware typography: text that looks like code (indentation, braces,
paths, JSON) is set in SF Mono; prose stays in SF Pro. URLs show the host in
`ink` and the path in `inkMuted`.

### Layout

A single floating panel, ~720 × 460 pt, centered on the active screen
(or, per Settings, at the pointer or below the menu bar icon; always inside
the screen's visible frame). Two panes under one search bar, a quiet footer.

```
┌──────────────────────────────────────────────────────────────────────┐
│  ⌕  Search                                         All  Text  Images  │  search bar, 52pt
├────────────────────────────────┬─────────────────────────────────────┤
│ 1  Meeting notes for Thursday… │                                     │
│ 2  github.com/kept/issues/12   │   Full content of the selection     │
│ 3  ▧  Screenshot  1440 × 900   │   (wrapped text, fitted image,      │
│ 4  ■  #FF6A00                  │    file icon + path)                │
│ 5  ~/Documents/report.pdf      │                                     │
│ 6  func makeBody() { …         │                                     │
│    …                           │   From      Safari                  │
│                                │   Copied    2 minutes ago           │
│                                │   Size      142 characters          │
├────────────────────────────────┴─────────────────────────────────────┤
│  ⏎ Paste   ⌥⏎ Paste as plain text   ⌘P Pin   ⌘⌫ Delete                 │  footer, 30pt
└──────────────────────────────────────────────────────────────────────┘
```

- Everything is **left aligned** to a 12pt gutter; the list's text column
  starts at the same x as the search text so the eye drops straight down.
- List rows are 34pt, single line. The leading gutter holds the quick-paste
  number (1–9) — the numbers are real shortcuts (⌘1–⌘9), not decoration.
- Pinned clips sit above the rest, separated by a hairline, each with a small
  marker-colored notch on the leading edge.
- The preview pane shows the full clip and a small two-column fact list
  (label / value). No meta strings joined with dots.
- Empty states say what to do: "Copy something and it shows up here."

**As built.** Details the wireframe leaves open:

- Rows: number · kind glyph (swatch, thumbnail, file icon) · title ·
  age · source app icon. The icons form one column on the trailing edge
  and the age sits against them, so titles get the width.
- The highlighter marks the row's *text* only, never the glyph, and runs a
  little past both ends with the icon's chisel slant. The marked text
  (host and path, code, semibold matches, the "…") takes the marked inks:
  dark on yellow in dark mode. The active filter token gets the same mark,
  smaller.
- Filter tokens are quiet text at the end of the search bar, not a
  segmented control.
- The footer shows only hints that apply now; with nothing selected it
  says "esc Close" (or "esc Clear search"), and "⌘⌫ Delete" only while
  the search is empty. Clearing history replaces the footer with an
  inline confirmation ("Clear 13 unpinned clips? Pinned clips stay."
  ⌥⌘⌫ Clear history · esc Cancel), never a modal, which would activate
  Kept.
- While searching, the words of the query that match a row's title are
  set semibold, same size and ink: no color, no underline (case-,
  diacritic- and width-insensitive, like the search). When a text row's
  first match sits past where the row truncates, the row starts with "…"
  just before it.
- The footer names what the keys do with the current settings: "⏎ Paste
  ⌥⏎ Paste as plain text ⌘⏎ Copy"; with "always paste plain text" ⏎ and
  ⌥⏎ swap ("Paste as plain text" / "Paste with formatting"); with "paste
  directly" off the verbs become "Copy" and ⌘⏎ isn't shown.
- Snapshots of every state, light and dark, come from
  `Kept --render-snapshots <dir>` (CI artifact `panel-snapshots`); they
  draw on the opaque window background because vibrancy doesn't render
  offscreen.

**As built: naming and editing clips.** Pins become snippets: a
clip can carry a name, and text can be corrected in place.

```
│ 1  Support reply  Thanks for reaching out…     │   a named row: the name in ink,
│ 2  ▧ [Studio address            ]   9d  ◉      │   the content muted after it
│                                                │   ⌘R: a native rounded field
├────────────────────────────────────────────────┤
│ ⏎ Rename   esc Cancel           Leave it empty to remove the name. │
```

- **Rename (⌘R).** The selected row's title becomes a native rounded text
  field after the clip's glyph (swatch, thumbnail, file icon), its text
  lined up with the other rows' where there's no glyph. It holds the
  current name or title, all selected, so typing replaces it; emptied, its
  placeholder is the clip's own title, which is what an empty name brings
  back. No highlighter while renaming: the field is the focus. ⏎ saves,
  Esc cancels the rename (a second Esc closes the panel), clicking
  anywhere else saves, as in Finder.
- **Named rows** show the name in ink, then the content muted (a link's
  address, a color's value, an image's size), after the same glyph; search
  matches the name and the content. The preview is unchanged except for a
  last, quiet fact, "Content", with the first line of what the clip holds.
- **Edit (⌘E).** For text, rich text, links and colors the preview becomes
  the editor: the same type (13 pt SF Pro for prose; 12 pt SF Mono for
  code, links and colors), its text where the preview's was, on the wash
  with a hairline edge and 6 pt corners, the facts hidden. Rich text adds
  one 11 pt muted line under it: "Saving keeps the text and drops the
  formatting." No smart quotes, dashes or autocorrection: code and URLs
  stay as typed. ⌘S (or ⌘⏎) saves in place and keeps the clip selected;
  ⏎ and Tab type; Esc cancels. Moving away (another row, the search, the
  filter, closing the panel) saves.
- **Images and files** can't be edited: ⌘E puts "Images can't be edited.
  ⌘R renames it." in the footer instead of a beep.
- **The footer** while renaming or editing is a bar like the clear
  confirmation: "⏎ Rename" or "⌘S Save", then "esc Cancel" (both
  clickable), and on the right a notice or, while renaming, "Leave it
  empty to remove the name." Notices stay near 40 characters so the key
  hints beside them never push them out. The usual footer doesn't list ⌘R and
  ⌘E, to stay short; the context menu and this file do.
- While a name or text is edited, every other ⌘ shortcut is taken and
  does nothing (no ⌘1–9 paste, no ⌘P pin), and the keyboard returns to
  the search field afterwards. VoiceOver reads the name in row labels and
  hears "Renamed to …", "Name removed." and "Edit saved."
- Snapshots: `selected-named-*`, `rename-*`, `rename-image-*`,
  `edit-text-*`, `edit-code-*`, `edit-rich-text-*`,
  `edit-image-refused-*`.

**As built: the copy-only hint.** When Kept copies but can't paste
(no permission yet, secure input, Kept itself in front), a small HUD
appears just above the bottom edge of where the panel was (or near the
bottom of the active screen for the global shortcut):

```
┌──────────────────────────────────────────┐
│ Copied. Press ⌘V to paste.               │   13pt medium, ink; ⌘V as a key cap
│ To paste for you, Kept needs Accessibility│   12pt, inkMuted (first time only)
│ access in Privacy & Security settings.   │
│                    [Allow Kept to paste…] │   small native button
└──────────────────────────────────────────┘
```

- The panel's vibrancy, 12pt corners, a hairline edge and the system
  shadow; 12pt padding; 300pt wide with the explanation, as wide as its
  line without. It never takes the keyboard, so ⌘V goes to the app.
- The explanation and button appear once; after that the hint is just
  "Copied. Press ⌘V to paste." for 2.5 s and lets clicks through. The
  first one stays 8 s, longer while the pointer is over it.
- Up to macOS 26 it names Accessibility; from macOS 27 (renamed and split
  pane) it says "Kept needs your permission in Privacy & Security
  settings", which is right whichever part lists PostEvent.
- Fades in and out in 120 ms, not at all under Reduce Motion; VoiceOver
  announces it, since it never takes focus.

### Principles

1. **Keyboard first.** Every action has a key and the footer shows it.
   The mouse works, but it's never required.
2. **Content shows itself.** A color shows its swatch, an image its
   thumbnail, a file its icon, a link its host, code its monospace.
   Kind is communicated by the rendering, not by labels.
3. **One mark.** The highlighter is the only brand color; it marks the
   selection and pins. Everything else is native and neutral.
4. **Native materials.** System font, vibrancy, semantic colors; respects
   light/dark, Reduce Motion, Reduce Transparency and Increase Contrast.
5. **Quiet motion.** Only the panel's appearance animates (≤120 ms fade +
   0.98→1 scale, off under Reduce Motion), and the copy-only hint fades
   in and out the same way. Selection moves instantly.

## Review against the defaults

| Default we'd reach for           | Decision |
|----------------------------------|----------|
| System-blue selection bar        | Replaced with the highlighter swipe behind text — on-subject (marking what you keep) and instantly recognisable. |
| Kind labels / colored type badges | Dropped. Rendering conveys kind (swatch, thumbnail, monospace, host/path). |
| Card grid of clips (Paste-style) | Dropped. A dense list is faster to scan by keyboard and fits more on screen. |
| Footer with "A · B · C" meta     | Facts live in a label/value list in the preview; footer only holds shortcut hints. |
| Monospace for small data labels  | Mono is only used where content is code-like; numbers use monospaced *digits* of SF Pro. |
| Decorative gradients / shadows   | None. Native window shadow only. |
| Clipboard / paperclip app icon   | The marked line: a short list with one line swiped by the highlighter (see [Icon](#icon)). |

## Keys

The search field always has focus, so plain letters and ⌫ edit the query;
every list action uses a modifier (⌘⌫ deletes a clip, ⌘P pins). Keys
that destroy something never share a habit with typing or pasting: ⌘⌫
deletes the clip only while the search is empty (with a query it deletes
to the start of the line, as in any field), and the clear bar takes only
⌥⌘⌫ again or its button, never ⏎.

In the panel, as built:

| Keys | Action |
|---|---|
| ↑ ↓ · ⌃P ⌃N | Move the selection |
| ⌘↑ ⌘↓ · Home End · PgUp PgDn | First, last, a page |
| ⏎ · ⌥⏎ · ⌘⏎ | Paste · the other format · copy only |
| ⌘1–⌘9 · ⌥⌘1–⌥⌘9 | Paste row N · in the other format |
| ⌘P | Pin / unpin |
| ⌘R | Rename the selected clip (⏎ saves, Esc cancels; empty shows its text again) |
| ⌘E | Edit the selected clip's text (⌘S or ⌘⏎ saves, Esc cancels; text, links, colors) |
| ⌥⌘↑ ⌥⌘↓ | Move the selected pin up / down (also: drag a pin) |
| ⌘⌫ | Delete the selected clip (empty search only) |
| ⌥⌘⌫, then ⌥⌘⌫ again | Clear unpinned clips (inline confirm; esc cancels, ⏎ does nothing) |
| Tab ⇧Tab | Next / previous type filter |
| ⌃U · Esc | Clear the search · clear, then close |
| ⌘, | Settings |

The footer keeps to the keys that act on the selection; moving pins,
renaming, editing and ⌘, live here and in the row's context menu instead,
so it stays quiet. Right-clicking a row offers Paste, Paste as plain text,
Copy · Pin / Unpin, Rename…, Edit… (text, links and colors only) ·
Delete, with their keys, named as the footer names them.

## Menu bar

- Template glyph in the menu bar (monochrome, adapts to light/dark): the
  app icon's marked line (see [Icon](#icon)). While capture is paused the
  marker turns hollow.
- Click → the same panel, anchored under the status item (whatever the
  panel position setting says; that's for the shortcut).
- Right-click (or ⌃- or ⌥-click) → a small menu:

```
Open Kept                ⇧⌘V     (the recorded shortcut)
──────────────────────
Pause capture                    (Resume capture while paused)
Ignore next copy                 (checked while armed; off while paused)
Clear history…                   (opens the panel's inline confirmation)
──────────────────────
Settings…                ⌘,
──────────────────────
Quit Kept                ⌘Q
```

- Relaunching Kept, and ⌘, in the panel, open Settings: macOS 26 can hide
  the icon, and those are the ways back in.
- The icon can be ⌘-dragged out of the menu bar, and Settings › General
  has "Show Kept in the menu bar". Both set one preference the item
  follows; relaunching Kept turns it back on, so the icon can always be
  restored.

## Icon

**Concept: the marked line.** Three lines of a clip history, the middle one
swiped with the highlighter: the thing you meant to keep, marked the same way
the panel marks its selection. No clipboards, paperclips or copy squares.

| Token      | Value                         | Use |
|------------|-------------------------------|-----|
| `graphite` | `#363940` → `#202227`         | Body, lit from the top; also the ink of the marked line |
| `paper`    | `#E4E4E0`                     | The unmarked lines |
| `marker`   | `#FFD84D`                     | The swipe, the icon's only color |
| `rim`      | white, 14% → 4%, 4 px inside  | Keeps the edge visible on dark backgrounds |

- **Shape.** Standard macOS grid: 1024 px canvas, 824 px body at 100 px
  with continuous corners (radius 185.4). No baked shadow, so the system
  sees the standard shape and adds its own depth.
- **The marker** has chisel-tip ends cut at the same angle and runs past
  the end of the text, the way a real highlighter does. Unmarked lines are
  paper on graphite; the marked line is ink on the marker.
- **Small sizes.** `AppIcon-32.svg` (32 px and 16 pt @2x) and
  `AppIcon-16.svg` (16 px) redraw the same picture on the pixel grid: whole
  pixel lines, single-pixel steps for the chisel ends at 16 px.
- **Menu bar.** `MenuBarIcon` (in `Sources/Kept/MenuBar/`) draws the same
  idea in code as a 20 × 18 pt template image: two lines and a solid marker
  with the middle line knocked out of it. `MenuBarIcon.image(paused: true)`
  draws the marker hollow, with the line inside, for "capture paused".

**Regenerate.** The SVGs in `Resources/Icon/` are the source of truth;
`Resources/AppIcon.icns` is generated from them and committed, so `make app`
needs no extra tools. After editing an SVG:

```sh
pip install pillow cairosvg     # on macOS, CairoSVG also needs: brew install cairo
scripts/make-icon.py            # renders every size, writes Resources/AppIcon.icns
scripts/make-icon.py --iconset /tmp/AppIcon.iconset   # also keep the PNGs to look at
```

The script uses `iconutil` on macOS and its own .icns writer elsewhere.
Commit the SVG and the .icns together.

## Settings window

Standard macOS settings window with a toolbar of panes. System controls
only; copy in sentence case, active voice.

**As built.** A titled window with a preference-style toolbar:
General · Shortcuts · Privacy · About (SF Symbols gearshape, command,
hand.raised, info.circle). The title follows the pane. Every pane is
560 pt wide; the window takes each pane's height and keeps its top edge
in place (animated, except under Reduce Motion). It opens on the last
pane used.

- Classic two-column layout: right-aligned labels with colons ("Startup:"),
  controls beside them on the first line's baseline, a fixed label column
  per pane, the form centered in the window, 20 pt above and below, 18 pt
  between rows, 6 pt within one.
- Explanations sit under their control in 11 pt secondary text, wrapped at
  the 330 pt controls column and, under a checkbox, indented to its title.
  They say what the control does, not what it is.
- **General** — Startup: Open Kept at login (with an "Open Login Items…"
  button and a note when macOS wants approval or registering failed, which
  unsigned builds often do). Menu bar: Show Kept in the menu bar, with a
  note naming the recorded shortcut and that opening Kept again brings the
  icon back. History size: a menu of 100 / 250 / 500 /
  1,000 / 2,500 / 5,000 / 10,000 clips. Pasting: Paste into the active app,
  with a line saying what happens now and "Open Privacy & Security…" while
  the permission is missing; Always paste as plain text. Open Kept: center
  of the active screen / at the mouse pointer / below the menu bar icon.
- **Shortcuts** — a recorder per global shortcut (Open Kept, Paste
  clipboard as plain text, Pause or resume capture), each with what it
  does; a closing note to include ⌘ or ⌃.
- **Privacy** — Clipboard (only on macOS 15.4+ when macOS asks or denies
  Kept's clipboard reads): "Kept can't see what you copy until you allow
  it.", where to change it (Privacy & Security › Paste from Other Apps;
  from macOS 27 "look for" it, since the pane may move) and "Open Privacy
  & Security…". Capture: Pause capture, Ignore copies from other devices,
  Keep images, Keep files. Excluded apps: a bordered list (app icon and
  name; a missing app dimmed with "Not installed", named from a small
  table for the default password managers, else by bundle ID, which the
  row's tooltip always shows) with borderless
  + and − below it and "Restore defaults" on the right, as in System
  Settings. History: "Forget unpinned clips:" with a menu (Never, After a
  day, After a week, After a month) and a one-line note ("Unpinned clips
  stay until your history is full." / "Counted from a clip's last copy or
  paste. Pinned clips stay."), applied at once; then "Clear history…" and a
  one-line summary ("13 clips in your history, 2 of them pinned.").
- **About** — the 96 pt icon, the name, "Version 0.1.0 (128)", one line of
  what Kept is, the project link, the license, a small "Show welcome
  window" button; a quiet note only when the history skipped unreadable
  clips or couldn't open.
- Snapshots: `settings-<pane>-light/dark.png` for each pane (General also
  with the approval and permission notes showing, Privacy also with
  "After a week", `settings-privacy-forget-week-*`) and
  `settings-window-light.png` with the title bar and toolbar.
- Closing Settings gives the keyboard back to the last app the user was
  in (even one they switched to while Settings was open), or hides Kept
  when there's none, so Kept never stays active with no window.
- Clearing from Settings asks with an alert (Settings is already active):
  "Clear history" keeps pins and is the default, "Clear everything" is
  marked destructive, "Cancel" answers Esc. With no pins there are only
  "Clear history" and "Cancel".

## Welcome window

**As built.** Opens once, by itself, at the first launch
(`welcomeShown`), and again from About. A titled window with a transparent
title bar, 380 pt wide, everything centered like a modern alert:

```
              [72 pt icon]
        Kept is in your menu bar                       17 pt semibold
  Press ⇧⌘V in any app, or click Kept's icon           13 pt, the shortcut
  in the menu bar, to see what you've copied.          as recorded, semibold
  Pasting into other apps needs your permission.       11 pt secondary
  Kept asks for it the first time you paste.
  ┌ Kept can't see what you copy until you allow it. ┐  only when macOS
  │ …Privacy & Security › Paste from Other Apps…     │  asks or denies
  └             [Open Privacy & Security…]           ┘  (wash, hairline)
           ☐ Open Kept at login
          [  Done  ]   [ Open Kept ]                   large, Open Kept default
```

- No marketing, no feature tour: where Kept is, how to open it, the one
  permission it will ask for, and login.
- "Open Kept" (the default button, ⏎) closes the window, waits for
  activation to go back to the user's app, then opens the panel, so its
  first paste lands there. "Done" (esc) closes it and returns focus like
  Settings.
- Snapshots: `welcome-light/dark.png`, `welcome-clipboard-denied-*`, and
  `settings-privacy-clipboard-access-*`.

## Accessibility

- VoiceOver: each row is one element, "Link, github.com/…, 9 minutes ago,
  from Safari, pinned", marked selected, that pastes when activated and
  offers Paste, the other format, Pin / Unpin and Delete as actions. The
  search field keeps the keyboard, so moving the selection (and opening
  the clear bar) is announced: the row's label and "4 of 15".
- Reduce Motion: no fades or scale. Reduce Transparency: the panel draws
  the opaque window background itself. Increase Contrast: the stronger
  marker and ink above (`search-increased-contrast-*` snapshots).
- Keyboard focus is visible where it moves (Settings, the welcome window:
  system controls); in the panel the highlighter is the focus.

## Writing

- Sentence case everywhere. Buttons say what happens: "Paste", "Pin",
  "Clear history".
- Errors say what happened and what to do: "Kept needs Accessibility access
  to paste for you. Open System Settings → Privacy & Security →
  Accessibility and turn on Kept."

## Website

The product site lives in `site/` (static HTML built with Astro, hosted on
Vercel). It is the app's page on the web, so everything above applies: one
mark, the system font, one left edge, quiet motion, the same writing. This
section holds what the web needs that the app gets from macOS.

### Brief

- **Subject:** what Kept is, how it works, how to get it.
- **Audience:** someone on a Mac deciding whether to install a clipboard
  manager, and the search engines and AI assistants they ask.
- **Primary job:** understand Kept in ten seconds, try it, download it.

### Color

A web page has no vibrancy to sit on, so the site names the neutrals the app
borrows from the system. They come from the icon: paper and graphite. The
marker tokens (`marker`, `markedInk`, `markedInkMuted`, `markerInk`,
`markerNotch`) are the app's, unchanged.

| Token      | Light                   | Dark                    | Role |
|------------|-------------------------|-------------------------|------|
| `page`     | `#F6F6F4`               | `#17181C`               | Page background |
| `surface`  | `#FFFFFF`               | `#202227`               | The panel |
| `ink`      | `#1C1C1E`               | `#ECECE8`               | Text |
| `inkMuted` | `#636366`               | `#A1A1A6`               | Fact labels, notes, captions |
| `inkFaint` | `#8E8E93`               | `#6C6C70`               | Quick-paste numbers, placeholders; never the only carrier of meaning |
| `hairline` | black @ 10%             | white @ 12%             | Section rules, the panel's dividers |
| `wash`     | black @ 5%              | white @ 8%              | Key caps, code |
| `button`   | `#202227`, text `#FFFFFF` | `#E4E4E0`, text `#202227` | The download button: graphite or paper, never the marker |

The site follows the system's light or dark setting and has no switch of its
own. `ink` on `page` is ≈15:1 in both; `inkMuted` clears 4.5:1 on `page` and
on `surface`.

**Where the marker goes.** It still means "this is selected": the selected
row and the active filter in the live panel, the current page in the header
(the active filter's small mark), and a text link under the pointer or the
keyboard. Drawn as in the app: behind the text, a little past both ends,
with the chisel slant (about 16° off vertical), never a solid control fill.
Yellow on the light page is about 1.2:1, so the marker never shows keyboard
focus by itself: under the keyboard a text link gets the marker and a 2 px
`markedInk` underline (dark on the yellow in both schemes), and anything
that isn't a text link gets a 2 px `ink` outline, 2 px away.

### Type

The system font here too (`-apple-system, BlinkMacSystemFont, system-ui,
"Segoe UI", Roboto, sans-serif`; code in `ui-monospace, "SF Mono", Menlo,
Consolas, monospace`). Everyone who can install Kept is reading on a Mac, so
the page is set in the same face as the app, loads no font files and asks no
third party for one.

| Style     | Spec                                                        | Use |
|-----------|-------------------------------------------------------------|-----|
| `display` | 40 → 64 px with the window, semibold, −0.025em, line 1.04   | The one headline |
| `title`   | 28 px, semibold, −0.018em, line 1.15                        | Section headings |
| `heading` | 17 px, semibold                                             | Questions, sub-heads |
| `body`    | 17 px, regular, line 1.55                                   | Prose, fact values |
| `label`   | 15 px, regular, inkMuted                                    | Fact labels |
| `small`   | 14 px, regular, inkMuted, line 1.45                         | Notes, captions, footer |
| `key`     | 12 px, medium, in a key cap (wash, hairline, 5 px corners)  | Shortcuts |
| `code`    | 14 px mono                                                  | Commands, paths, hex values |

Mono is for code-like content only, as in the app. Prose wraps at about 62
characters. The live panel keeps the app's own sizes, 1 pt = 1 CSS px.

### Layout

One column, the width of the panel (720 px, plus a 24 px gutter each side),
centered in the window the way the panel is centered on the screen. Inside
it everything starts on the same left edge: headline, prose, the panel,
fact labels. Sections are separated by space (96 px, 64 px on a phone) and
one hairline; there are no cards, no icon grids and no second column of
marketing.

```
 ▣ Kept                                        Shortcuts  Privacy  GitHub

 You copied it.
 Kept kept it.

 Kept is a clipboard history for the Mac. Press ⇧⌘V in any app,
 type a few letters, press ⏎, and what you copied an hour ago is
 back where you were typing.

 [ Download Kept ]  Version 0.1.0 for macOS 14 or later. Free.

 ┌──────────────────────────────────────────────────────────────────┐
 │ ⌕ Search                           All  Pinned  Text  Links  …   │
 ├───────────────────────────────┬──────────────────────────────────┤
 │ ▍1  1 Ferry Building, San F…  │                                  │
 │  5  ▧ ▰Image 1440 × 900▰      │   the selected clip, in full     │
 │  6  func write(_ items: [N…   │   From     Preview               │
 ├───────────────────────────────┴──────────────────────────────────┤
 │ ⏎ Paste   ⌥⏎ Paste as plain text   ⌘⏎ Copy   ⌘P Pin              │
 └──────────────────────────────────────────────────────────────────┘
 This one works. Press ⇧⌘V or click it, then ↑ ↓, type, ⏎.
 ▍ what you paste lands on this line

 ──────────────────────────────────────────────────────────────────
 What it does

 Keeps      Text, rich text, links, images, files and colors.
 Finds      Type to search. Matching words are set in bold.
 Pastes     ⏎ pastes into the app you were in. ⌥⏎ pastes plain text.
 ──────────────────────────────────────────────────────────────────
 Keys · Privacy · Screenshots · Install (numbered: it's a sequence) ·
 Questions · Open source · Download again · footer
```

- **Fact lists.** Features and privacy are label / value lists, the
  preview pane's fact list at reading size: a 144 px label column in
  `inkMuted`, the value beside it in `ink`. On a phone the label sits above
  its value. No icons, no cards.
- **Numbers** appear only where order is real: the install steps and the
  panel's quick-paste column.
- **Header.** The icon and the name on the left edge; on the right, quiet
  text links like the panel's filter tokens, the current page marked. Not
  sticky.
- **Screenshots** are the README's own files (`docs/images/`), so there is
  one copy to update. They carry their window shadow; the page adds none.

### The live panel

The hero is the panel itself, rebuilt in HTML and working: the most
characteristic thing Kept has is the marked line, and a keyboard-first app
is best explained by letting someone use the keyboard.

- It is drawn from this document's tokens and layout at the app's size
  (720 × 460, 52 px search bar, 34 px rows, 30 px footer, 324 px list) and
  filled with the snapshot history from `SampleHistory.swift`.
- It opens with the image selected, as in the README. ↑ ↓ (and ⌃P ⌃N) move
  the mark, typing searches and sets matches semibold, the filter tokens
  filter, ⌘P pins, ⌘⌫ deletes while the search is empty, Esc clears the
  search and then leaves the panel. ⏎, ⌥⏎ and ⌘⏎ do what the footer says.
  ⇧⌘V anywhere on the page puts the keyboard in it, as it would open Kept.
- **Pasting** closes the panel as the app does and puts the clip on the
  line under it, the stand-in for wherever you were typing; the panel comes
  back by itself. The demo never touches the visitor's real clipboard.
  The line's "What you paste lands here." is `inkMuted`, not `inkFaint`:
  nothing else says what the line is for.
- **Where it differs from the app, so a demo reads.** ⌘⏎ shows the
  copy-only hint ("Copied. Press ⌘V to paste."), and ⌘V while it shows
  puts the clip on the line; the app copies quietly on ⌘⏎. After a paste
  the panel keeps its search, filter and selection instead of starting
  fresh, and the history doesn't reorder. Once someone has pinned, unpinned
  or deleted, a quiet "Reset" appears beside the hint.
- **What it leaves out, on purpose.** Source-app icons (they are other
  people's artwork; the preview names the app in text instead), Tab to
  change the filter (Tab must keep moving through the page), and ⌘1–⌘9,
  ⌘R and ⌘E (the browser owns them). The numbers still show, and clicking
  works everywhere.
- Without JavaScript it is a still picture of the same state, made of
  real text. Below 760 px it shows the list pane only and rows are tapped.
- The only window shadows on the site are the panel's and its copy-only
  hint's (the app's hint has the system shadow too). With the keyboard in
  it the panel looks like a key window (a firmer edge, a deeper shadow),
  not a focus ring; the caret is the focus. For assistive technology it is
  a combobox with a listbox; result counts, pastes, pins and deletes are
  announced.

### Motion

As in the app, only the panel and its copy-only hint move: the panel fades
out when a paste or a copy closes it and fades and scales back in (≤120 ms,
0.98 → 1), and the hint fades in and out the same way. The caret on the
paste line blinks. Selection, filters and hover change instantly. Under
Reduce Motion nothing animates.

### Writing

The rules above, plus the web's own traps: no label above a heading, no
"A · B · C" strings of facts, no arrow after a link, no claim the README
can't back. The button is "Download Kept" wherever it appears. Say what
Kept does in the words of someone who copies and pastes; version, system
requirements and price are a sentence, not a badge row.

### Review against the defaults

| Default we'd reach for                    | Decision |
|-------------------------------------------|----------|
| Screenshot in a browser frame as the hero | The panel itself, live: you learn Kept by pressing ↓ and ⏎. |
| A display typeface for personality        | The system font, as in the app; the page looks like the thing it sells and loads nothing. |
| Three-column feature cards with icons     | A fact list, the preview pane's own form. |
| Yellow download button                    | Graphite (paper in dark mode). The marker stays a highlighter. |
| A highlighted word in the headline        | The mark means selection, so it lives in the panel and on what you point at, not on a slogan. |
| Fade-in on scroll for every section       | Only the panel and its hint move, opening and closing. |
| Light/dark switch, cookie banner, analytics | Follows the system; sets no cookies and loads nothing from third parties. |
