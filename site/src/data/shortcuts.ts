// Keyboard shortcuts, from README.md › Keyboard shortcuts. Where the README
// packs several actions into one row ("⏎ · ⌥⏎ · ⌘⏎"), they get a row each.
// `keys` and `action` use the inline convention in src/lib/inline.ts: each
// {…} is one key cap; caps of one group are joined by no-break spaces
// (\u00a0), and so are "or" and "then" to the group after them, so a
// narrow column wraps only before "or" or "then". `essential` marks
// the keys the home page lists.

export interface Shortcut {
  keys: string;
  action: string;
  essential?: boolean;
  /** The keys in short, where the home page's list has less room. */
  short?: string;
}

export const globalShortcuts: Shortcut[] = [
  { keys: '{⇧⌘V}', action: 'Open or close Kept', essential: true },
  { keys: 'None by default', action: 'Paste the clipboard as plain text' },
  { keys: 'None by default', action: 'Pause or resume capture' },
];

export const panelShortcuts: Shortcut[] = [
  { keys: 'Type', action: 'Search' },
  { keys: '{↑}\u00a0{↓} or\u00a0{⌃P}\u00a0{⌃N}', short: '{↑}\u00a0{↓}', action: 'Move the selection', essential: true },
  { keys: '{⌘↑} or\u00a0{Home}', action: 'First clip' },
  { keys: '{⌘↓} or\u00a0{End}', action: 'Last clip' },
  { keys: '{PgUp}\u00a0{PgDn}', action: 'A page up or down' },
  { keys: '{⏎}', action: 'Paste', essential: true },
  { keys: '{⌥⏎}', action: 'Paste as plain text', essential: true },
  { keys: '{⌘⏎}', action: 'Copy without pasting', essential: true },
  { keys: '{⌘1}–{⌘9}', action: 'Paste clip 1 to 9', essential: true },
  { keys: '{⌥⌘1}–{⌥⌘9}', action: 'Paste clip 1 to 9 as plain text' },
  { keys: '{⌘P}', action: 'Pin or unpin', essential: true },
  { keys: '{⌘R}', action: 'Rename the selected clip ({⏎} saves, {esc} cancels)' },
  { keys: '{⌘E}', action: 'Edit the selected clip’s text ({⌘S} saves, {esc} cancels)' },
  { keys: '{⌥⌘↑}\u00a0{⌥⌘↓}', action: 'Move a pinned clip up or down (or drag it)' },
  { keys: '{⌘⌫}', action: 'Delete the selected clip (when the search is empty)' },
  { keys: '{⌥⌘⌫}, then\u00a0{⌥⌘⌫}', action: 'Clear all unpinned clips' },
  { keys: '{Tab}\u00a0{⇧Tab}', action: 'Next or previous type filter' },
  { keys: '{⌃U}', action: 'Clear the search' },
  { keys: '{esc}', action: 'Clear the search, then close', essential: true },
  { keys: '{⌘,}', action: 'Open Settings' },
];

/** The handful the home page shows, in the order above. */
export const essentialShortcuts: Shortcut[] = [...globalShortcuts, ...panelShortcuts]
  .filter((shortcut) => shortcut.essential)
  .map((shortcut) => ({ ...shortcut, keys: shortcut.short ?? shortcut.keys }));
