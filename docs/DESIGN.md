# Kept — Design

This is the design plan for Kept. It follows the two-pass process from the
frontend-design guidance: first a compact token system, then a review against
the generic defaults, then the build. Anything visual in the app should trace
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
| `marker`     | `#FFD84D` @ 60% under text    | `#E8B73A` @ 30% under text    | Selection highlight, pin notch |
| `markerInk`  | `#8A6A00`                     | `#F2C94C`                     | Pin glyph, active filter text |

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
(optionally at the cursor). Two panes under one search bar, a quiet footer.

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
   0.98→1 scale, off under Reduce Motion). Selection moves instantly.

## Review against the defaults

| Default we'd reach for           | Decision |
|----------------------------------|----------|
| System-blue selection bar        | Replaced with the highlighter swipe behind text — on-subject (marking what you keep) and instantly recognisable. |
| Kind labels / colored type badges | Dropped. Rendering conveys kind (swatch, thumbnail, monospace, host/path). |
| Card grid of clips (Paste-style) | Dropped. A dense list is faster to scan by keyboard and fits more on screen. |
| Footer with "A · B · C" meta     | Facts live in a label/value list in the preview; footer only holds shortcut hints. |
| Monospace for small data labels  | Mono is only used where content is code-like; numbers use monospaced *digits* of SF Pro. |
| Decorative gradients / shadows   | None. Native window shadow only. |

## Keys

The full shortcut map lives in [RESEARCH.md](RESEARCH.md#keyboard-shortcut-map).
The search field always has focus, so plain letters and ⌫ edit the query;
every list action uses a modifier (⌘⌫ deletes a clip, ⌘P pins).

## Menu bar

- Template glyph in the menu bar (monochrome, adapts to light/dark).
- Click → the same panel, anchored under the status item.
- Right-click (or ⌥-click) → small menu: Pause capture, Settings…, Quit.

## Settings window

Standard macOS settings window with a toolbar of panes (General, Shortcuts,
Ignore, Advanced). System controls only; copy in sentence case, active voice.

## Writing

- Sentence case everywhere. Buttons say what happens: "Paste", "Pin",
  "Clear history".
- Errors say what happened and what to do: "Kept needs Accessibility access
  to paste for you. Open System Settings → Privacy & Security →
  Accessibility and turn on Kept."
