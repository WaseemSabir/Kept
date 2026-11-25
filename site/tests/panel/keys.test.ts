import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { command, opensPanel, pastes, types, type KeyPress } from '../../src/scripts/panel/keys.ts';

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
