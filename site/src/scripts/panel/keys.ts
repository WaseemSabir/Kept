// Keys to commands, as PanelKeyRouter maps them, less what the browser owns
// (⌘1–⌘9, ⌘R, ⌘E) and Tab, which keeps moving through the page. Plain
// letters, ⌫ and ← → aren't commands: they edit the search. Letter
// shortcuts match the character the key types, as in the app.

export type Command =
  | 'up'
  | 'down'
  | 'first'
  | 'last'
  | 'page-up'
  | 'page-down'
  | 'paste'
  | 'paste-plain'
  | 'copy'
  | 'pin'
  | 'delete'
  | 'clear-search'
  | 'cancel';

/** The parts of a KeyboardEvent the panel reads. */
export interface KeyPress {
  key: string;
  metaKey: boolean;
  ctrlKey: boolean;
  altKey: boolean;
  shiftKey: boolean;
  isComposing?: boolean;
}

/** The modifiers held, in the Mac's order: "", "⌘", "⌥⌘", "⇧⌘"… */
function modifiers(press: KeyPress): string {
  return (press.ctrlKey ? '⌃' : '') + (press.altKey ? '⌥' : '') + (press.shiftKey ? '⇧' : '') + (press.metaKey ? '⌘' : '');
}

export function command(press: KeyPress): Command | undefined {
  // An input method is composing: its keys are its own.
  if (press.isComposing) return undefined;
  const held = modifiers(press);
  switch (press.key) {
    case 'ArrowUp':
      return held === '' ? 'up' : held === '⌘' ? 'first' : undefined;
    case 'ArrowDown':
      return held === '' ? 'down' : held === '⌘' ? 'last' : undefined;
    case 'Home':
      return held === '' ? 'first' : undefined;
    case 'End':
      return held === '' ? 'last' : undefined;
    case 'PageUp':
      return held === '' ? 'page-up' : undefined;
    case 'PageDown':
      return held === '' ? 'page-down' : undefined;
    case 'Enter':
      return held === '' ? 'paste' : held === '⌥' ? 'paste-plain' : held === '⌘' ? 'copy' : undefined;
    case 'Backspace':
    case 'Delete':
      return held === '⌘' ? 'delete' : undefined;
    case 'Escape':
      return held === '' ? 'cancel' : undefined;
  }
  const character = press.key.toLowerCase();
  if (held === '⌃') {
    if (character === 'p') return 'up';
    if (character === 'n') return 'down';
    if (character === 'u') return 'clear-search';
  }
  if (held === '⌘' && character === 'p') return 'pin';
  return undefined;
}

/** ⇧⌘V: opens Kept, so on the page it puts the keyboard in the panel. */
export function opensPanel(press: KeyPress): boolean {
  return modifiers(press) === '⇧⌘' && press.key.toLowerCase() === 'v';
}

/** ⌘V. */
export function pastes(press: KeyPress): boolean {
  return modifiers(press) === '⌘' && press.key.toLowerCase() === 'v';
}

/** A key that types a character into a field (a letter, a digit, a space). */
export function types(press: KeyPress): boolean {
  return !press.metaKey && !press.ctrlKey && [...press.key].length === 1;
}
