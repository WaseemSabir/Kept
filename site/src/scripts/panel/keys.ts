// Keys to commands, as PanelKeyRouter maps them, less what the browser owns
// (⌘1–⌘9, ⌘R, ⌘E) and Tab, which keeps moving through the page. Plain
// letters, ⌫ and ← → aren't commands: they edit the search. Letter
// shortcuts match the character the key types, as in the app. ⌃P ⌃N ⌃U are
// the Mac's text keys; on other systems ⌃P prints and ⌃N opens a window, so
// there they're left to the browser.

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
  /** 229 for a key an input method takes. */
  keyCode?: number;
}

/** The system the page runs on, as far as the keys care. */
export type Platform = 'mac' | 'other';

/** What the browser says about its system; any of it may be missing. */
export interface PlatformHints {
  /** `navigator.userAgentData.platform` (Chromium): "macOS", "Windows"… */
  userAgentData?: string | undefined;
  /** `navigator.platform`: "MacIntel", "Win32", "Linux x86_64"… */
  platform?: string | undefined;
  userAgent?: string | undefined;
}

/** A Mac or not: the client hint when there is one, else `navigator.platform`, else the user agent. */
export function platformFrom(hints: PlatformHints): Platform {
  if (hints.userAgentData) return hints.userAgentData === 'macOS' ? 'mac' : 'other';
  if (hints.platform) return /^mac/i.test(hints.platform) ? 'mac' : 'other';
  return /\bMacintosh\b/.test(hints.userAgent ?? '') ? 'mac' : 'other';
}

/**
 * An input method has the key, so it isn't ours. Safari fires
 * compositionend before the keydown of the ⏎ that confirms the text, and
 * that keydown has isComposing false but keyCode 229.
 */
export function composing(press: KeyPress): boolean {
  return press.isComposing === true || press.keyCode === 229;
}

/** The modifiers held, in the Mac's order: "", "⌘", "⌥⌘", "⇧⌘"… */
function modifiers(press: KeyPress): string {
  return (press.ctrlKey ? '⌃' : '') + (press.altKey ? '⌥' : '') + (press.shiftKey ? '⇧' : '') + (press.metaKey ? '⌘' : '');
}

export function command(press: KeyPress, platform: Platform): Command | undefined {
  if (composing(press)) return undefined;
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
  if (held === '⌃' && platform === 'mac') {
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
