import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import {
  isEmpty,
  isPinned,
  isSearching,
  keptIndex,
  movedIndex,
  pin,
  remove,
  sectionBreak,
  startingHistory,
  togglePin,
  unpin,
} from '../../src/scripts/panel/history.ts';
import { searchResults } from '../../src/scripts/panel/search.ts';
import { clips, ids } from './helpers.ts';

const start = startingHistory(clips);
const listed = (history = start) => ids(searchResults('', 'all', history));

describe('pins', () => {
  test('a new pin goes to the end of the pinned section', () => {
    const history = pin(start, 'git-log');
    assert.deepEqual(ids(history.pinned), ['ferry', 'support-reply', 'git-log']);
    assert.ok(!ids(history.recent).includes('git-log'));
    assert.equal(history.pinned.at(-1)?.pinned, true);
    assert.deepEqual(listed(history).slice(0, 4), ['ferry', 'support-reply', 'git-log', 'turnaround']);
  });

  test('unpinning puts the clip at the top of the rest, copied now', () => {
    const history = unpin(start, 'ferry');
    assert.deepEqual(ids(history.pinned), ['support-reply']);
    const [top] = history.recent;
    assert.equal(top?.id, 'ferry');
    assert.equal(top?.pinned, false);
    assert.equal(top?.age, 'now');
    assert.equal(top?.copied, 'Just now');
    assert.equal(top?.minutesAgo, 0);
    assert.equal(top?.facts.find((fact) => fact.label === 'Copied')?.value, 'Just now');
    assert.deepEqual(listed(history).slice(0, 3), ['support-reply', 'ferry', 'turnaround']);
  });

  test('toggling switches, and does nothing for a clip that isn\'t there', () => {
    assert.ok(isPinned(togglePin(start, 'orange'), 'orange'));
    assert.ok(!isPinned(togglePin(start, 'ferry'), 'ferry'));
    assert.equal(pin(start, 'ferry'), start, 'already pinned');
    assert.equal(unpin(start, 'orange'), start, 'not pinned');
    assert.equal(togglePin(start, 'nope'), start);
  });

  test('changes never touch the history they started from', () => {
    togglePin(start, 'ferry');
    remove(start, 'orange');
    assert.deepEqual(listed(), ids(clips));
  });
});

describe('remove', () => {
  test('deletes pinned and unpinned clips', () => {
    const history = remove(remove(start, 'ferry'), 'orange');
    assert.ok(!listed(history).includes('ferry'));
    assert.ok(!listed(history).includes('orange'));
    assert.equal(listed(history).length, clips.length - 2);
  });

  test('an emptied history is empty', () => {
    const emptied = clips.reduce((history, clip) => remove(history, clip.id), start);
    assert.ok(isEmpty(emptied));
    assert.ok(!isEmpty(start));
  });
});

describe('sectionBreak', () => {
  test('falls under the pins when the list shows pins and the rest', () => {
    assert.equal(sectionBreak(searchResults('', 'all', start), '', 'all'), 2);
  });

  test('none while searching, on the Pinned filter, or with no pins', () => {
    assert.equal(sectionBreak(searchResults('', 'pinned', start), '', 'pinned'), undefined);
    assert.equal(sectionBreak(searchResults('e', 'all', start), 'e', 'all'), undefined);
    const unpinned = unpin(unpin(start, 'ferry'), 'support-reply');
    assert.equal(sectionBreak(searchResults('', 'all', unpinned), '', 'all'), undefined);
    assert.equal(sectionBreak(searchResults('', 'links', start), '', 'links'), undefined);
  });

  test('isSearching ignores a query of spaces', () => {
    assert.ok(!isSearching('   '));
    assert.ok(isSearching(' a '));
  });
});

describe('selection', () => {
  test('keeps the same clip when it moved', () => {
    const before = searchResults('', 'all', start);
    const after = searchResults('', 'all', pin(start, 'orange'));
    assert.equal(before[6]?.id, 'orange');
    assert.equal(keptIndex(after, 'orange', 6), 2);
  });

  test('takes the clip that took its place when it went, or the new last row', () => {
    const list = searchResults('', 'all', remove(start, 'orange'));
    assert.equal(list[keptIndex(list, 'orange', 6) ?? -1]?.id, 'invoices');
    assert.equal(keptIndex(list, 'gone', 99), list.length - 1);
    assert.equal(keptIndex([], 'orange', 0), undefined);
  });

  test('moves within the list', () => {
    assert.equal(movedIndex(15, 4, 1), 5);
    assert.equal(movedIndex(15, 0, -1), 0);
    assert.equal(movedIndex(15, 14, 1), 14);
    assert.equal(movedIndex(15, 4, 10), 14);
    assert.equal(movedIndex(15, 12, -10), 2);
    assert.equal(movedIndex(15, undefined, 1), 0, 'nothing selected: down picks the first');
    assert.equal(movedIndex(15, undefined, -1), 14, 'nothing selected: up picks the last');
    assert.equal(movedIndex(0, undefined, 1), undefined);
  });
});
