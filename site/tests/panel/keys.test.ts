import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import {
  command as commandOn,
  composing,
  opensPanel,
  pastes,
  platformFrom,
  types,
  type KeyPress,
} from '../../src/scripts/panel/keys.ts';

/** A key press: "⌘P" style modifiers before the key. */
function press(key: string, held = ''): KeyPress {
  return {
    key,
    metaKey: held.includes('⌘'),
    ctrlKey: held.includes('⌃'),
    altKey: held.includes('⌥'),
    shiftKey: held.includes('⇧'),
  };
}

/** Keys on a Mac, where most of the tests are. */
const command = (keyPress: KeyPress) => commandOn(keyPress, 'mac');

describe('command', () => {
  test('moves the selection', () => {
    assert.equal(command(press('ArrowUp')), 'up');
    assert.equal(command(press('ArrowDown')), 'down');
    assert.equal(command(press('p', '⌃')), 'up');
    assert.equal(command(press('n', '⌃')), 'down');
    assert.equal(command(press('ArrowUp', '⌘')), 'first');
    assert.equal(command(press('ArrowDown', '⌘')), 'last');
    assert.equal(command(press('Home')), 'first');
    assert.equal(command(press('End')), 'last');
    assert.equal(command(press('PageUp')), 'page-up');
    assert.equal(command(press('PageDown')), 'page-down');
  });

  test('pastes, pastes as plain text, copies', () => {
    assert.equal(command(press('Enter')), 'paste');
    assert.equal(command(press('Enter', '⌥')), 'paste-plain');
    assert.equal(command(press('Enter', '⌘')), 'copy');
    assert.equal(command(press('Enter', '⇧')), undefined);
  });

  test('pins, deletes, clears and cancels', () => {
    assert.equal(command(press('p', '⌘')), 'pin');
    assert.equal(command(press('P', '⌘')), 'pin', 'Caps Lock on');
    assert.equal(command(press('Backspace', '⌘')), 'delete');
    assert.equal(command(press('Delete', '⌘')), 'delete');
    assert.equal(command(press('u', '⌃')), 'clear-search');
    assert.equal(command(press('Escape')), 'cancel');
  });

  test('leaves typing, editing and what the browser owns alone', () => {
    for (const key of ['a', ' ', 'Backspace', 'ArrowLeft', 'ArrowRight', 'Tab']) {
      assert.equal(command(press(key)), undefined, key);
    }
    assert.equal(command(press('Tab', '⇧')), undefined);
    assert.equal(command(press('ArrowUp', '⇧')), undefined, '⇧↑ selects text');
    assert.equal(command(press('ArrowUp', '⌥⌘')), undefined, 'moving pins is left out');
    for (const key of ['1', '9', 'r', 'e', 'c', 'v', 'a', 'z']) {
      assert.equal(command(press(key, '⌘')), undefined, `⌘${key}`);
    }
    assert.equal(command(press('Backspace', '⌥⌘')), undefined, 'clearing history is left out');
    assert.equal(command(press('Escape', '⇧')), undefined);
    assert.equal(command(press('p')), undefined);
  });

  test('an input method that is composing keeps its keys', () => {
    assert.equal(command({ ...press('Enter'), isComposing: true }), undefined);
    assert.equal(command({ ...press('ArrowDown'), isComposing: true }), undefined);
  });

  test('so does the ⏎ that confirms a composition in Safari (keyCode 229, isComposing false)', () => {
    assert.equal(command({ ...press('Enter'), isComposing: false, keyCode: 229 }), undefined);
    assert.equal(command({ ...press('Escape'), keyCode: 229 }), undefined);
    assert.equal(command({ ...press('Enter'), keyCode: 13 }), 'paste');
  });

  test('⌃P ⌃N ⌃U only on a Mac: elsewhere they print, open a window, view source', () => {
    for (const key of ['p', 'n', 'u']) {
      assert.equal(commandOn(press(key, '⌃'), 'other'), undefined, `⌃${key}`);
    }
    assert.equal(commandOn(press('ArrowDown'), 'other'), 'down');
    assert.equal(commandOn(press('Enter'), 'other'), 'paste');
    assert.equal(commandOn(press('p', '⌘'), 'other'), 'pin', '⌘ keys are mapped as before');
  });
});

describe('composing', () => {
  test('while an input method has the key', () => {
    assert.ok(composing({ ...press('a'), isComposing: true }));
    assert.ok(composing({ ...press('Enter'), keyCode: 229 }));
    assert.ok(composing({ ...press('v', '⇧⌘'), keyCode: 229 }));
  });

  test('not for ordinary keys', () => {
    assert.ok(!composing(press('Enter')));
    assert.ok(!composing({ ...press('Enter'), isComposing: false, keyCode: 13 }));
    assert.ok(!composing({ ...press('v', '⇧⌘'), keyCode: 86 }));
  });
});

describe('platformFrom', () => {
  const macUserAgent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';

  test('prefers the client hint', () => {
    assert.equal(platformFrom({ userAgentData: 'macOS', platform: 'MacIntel' }), 'mac');
    assert.equal(platformFrom({ userAgentData: 'Windows', platform: 'MacIntel', userAgent: macUserAgent }), 'other');
    assert.equal(platformFrom({ userAgentData: 'Linux' }), 'other');
    assert.equal(platformFrom({ userAgentData: 'Chrome OS' }), 'other');
  });

  test('then navigator.platform', () => {
    assert.equal(platformFrom({ userAgentData: '', platform: 'MacIntel' }), 'mac');
    assert.equal(platformFrom({ platform: 'Win32', userAgent: macUserAgent }), 'other');
    assert.equal(platformFrom({ platform: 'Linux x86_64' }), 'other');
    assert.equal(platformFrom({ platform: 'iPhone' }), 'other');
  });

  test('then the user agent', () => {
    assert.equal(platformFrom({ platform: '', userAgent: macUserAgent }), 'mac');
    assert.equal(platformFrom({ userAgent: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36' }), 'other');
    assert.equal(
      platformFrom({ userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15' }),
      'other',
      'an iPhone says "like Mac OS X", not Macintosh',
    );
    assert.equal(platformFrom({}), 'other');
  });
});

describe('page keys', () => {
  test('⇧⌘V opens the panel; nothing else does', () => {
    assert.ok(opensPanel(press('v', '⇧⌘')));
    assert.ok(opensPanel(press('V', '⇧⌘')));
    assert.ok(!opensPanel(press('v', '⌘')));
    assert.ok(!opensPanel(press('v', '⇧⌥⌘')));
  });

  test('⌘V pastes', () => {
    assert.ok(pastes(press('v', '⌘')));
    assert.ok(!pastes(press('v', '⇧⌘')));
  });

  test('types tells characters from shortcuts', () => {
    assert.ok(types(press('a')));
    assert.ok(types(press('A', '⇧')));
    assert.ok(types(press('é', '⌥')));
    assert.ok(!types(press('a', '⌘')));
    assert.ok(!types(press('a', '⌃')));
    assert.ok(!types(press('Enter')));
  });
});
