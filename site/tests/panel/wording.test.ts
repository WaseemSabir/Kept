import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { pin, remove, startingHistory, unpin } from '../../src/scripts/panel/history.ts';
import { emptyState, footerHints, pasted, resultsPhrase } from '../../src/scripts/panel/wording.ts';
import { clipById, clips } from './helpers.ts';

const start = startingHistory(clips);

describe('emptyState', () => {
  test('a search with no results, in the app\'s words', () => {
    assert.deepEqual(emptyState(start, ' zebra ', 'all'), {
      title: 'No clips match “zebra”.',
      hint: 'Press Esc to clear the search.',
      spansPanel: false,
    });
    assert.equal(emptyState(start, 'zebra', 'links').title, 'No links match “zebra”.');
    assert.equal(emptyState(start, 'zebra', 'text').title, 'No text clips match “zebra”.');
    assert.equal(emptyState(start, 'zebra', 'pinned').hint, 'Press Esc to clear the search.', 'no Tab on the page');
  });

  test('shortens a long query to 40 characters', () => {
    const query = 'a'.repeat(50);
    assert.equal(emptyState(start, query, 'all').title, `No clips match “${'a'.repeat(40)}…”.`);
  });

  test('an emptied history takes the whole panel', () => {
    const emptied = clips.reduce((history, clip) => remove(history, clip.id), start);
    assert.deepEqual(emptyState(emptied, 'whatever', 'files'), {
      title: 'Copy something and it shows up here.',
      hint: 'Text, links, images and files you copy are kept here. Pin the ones you use often with ⌘P.',
      spansPanel: true,
    });
  });

  test('a filter with nothing in it', () => {
    const noPins = unpin(unpin(start, 'ferry'), 'support-reply');
    assert.deepEqual(emptyState(noPins, '', 'pinned'), {
      title: 'No pinned clips yet.',
      hint: 'Select a clip and press ⌘P to keep it at the top.',
      spansPanel: false,
    });
    const noImages = remove(start, 'landscape');
    assert.equal(emptyState(noImages, '', 'images').hint, 'Copy an image, or press ⌃⇧⌘4 to copy part of the screen.');
  });
});

describe('footerHints', () => {
  test('with a clip selected: its actions, Pin or Unpin, Delete only while the search is empty', () => {
    assert.deepEqual(footerHints(clipById('landscape'), ''), { actions: true, pin: 'Pin', delete: true });
    assert.deepEqual(footerHints(clipById('ferry'), ''), { actions: true, pin: 'Unpin', delete: true });
    assert.equal(footerHints(clipById('ferry'), 'f').delete, false);
    assert.equal(footerHints(clipById('ferry'), ' ').delete, false, '⌘⌫ edits a query of spaces too');
    const pinned = pin(start, 'landscape').pinned.at(-1);
    assert.equal(footerHints(pinned, '').pin, 'Unpin');
  });

  test('with nothing selected: what Esc does', () => {
    assert.equal(footerHints(undefined, 'zebra').esc, 'Clear search');
    assert.equal(footerHints(undefined, '').esc, 'Close');
    assert.equal(footerHints(undefined, '').actions, false);
  });
});

describe('resultsPhrase', () => {
  test('counts in the filter\'s noun', () => {
    assert.equal(resultsPhrase(15, 'all'), '15 clips.');
    assert.equal(resultsPhrase(1, 'all'), '1 clip.');
    assert.equal(resultsPhrase(2, 'links'), '2 links.');
    assert.equal(resultsPhrase(1, 'pinned'), '1 pinned clip.');
  });
});

describe('pasted', () => {
  test('text as text, code in monospace unless plain', () => {
    assert.deepEqual(pasted(clipById('git-log'), false), {
      kind: 'text',
      text: 'git log --oneline --graph --decorate -20',
      code: false,
      link: false,
    });
    const code = clipById('write-items');
    assert.deepEqual(pasted(code, false), { kind: 'text', text: code.content, code: true, link: false });
    assert.deepEqual(pasted(code, true), { kind: 'text', text: code.content, code: false, link: false });
  });

  test('a link as its address, a color as its value, files as their names', () => {
    assert.deepEqual(pasted(clipById('changecount'), false), {
      kind: 'text',
      text: 'https://developer.apple.com/documentation/appkit/nspasteboard/changecount',
      code: false,
      link: true,
    });
    assert.deepEqual(pasted(clipById('changecount'), true), {
      kind: 'text',
      text: 'https://developer.apple.com/documentation/appkit/nspasteboard/changecount',
      code: false,
      link: false,
    });
    assert.deepEqual(pasted(clipById('blue'), false), { kind: 'text', text: 'rgba(52, 120, 246, 0.5)', code: true, link: false });
    assert.deepEqual(pasted(clipById('invoices'), true), {
      kind: 'text',
      text: 'Invoice-2041.pdf\nInvoice-2042.pdf\nReceipts October.zip',
      code: false,
      link: false,
    });
  });

  test('an image pastes as a picture, plain or not', () => {
    assert.deepEqual(pasted(clipById('landscape'), false), { kind: 'image', label: 'Image 1440 × 900' });
    assert.deepEqual(pasted(clipById('landscape'), true), { kind: 'image', label: 'Image 1440 × 900' });
  });
});
