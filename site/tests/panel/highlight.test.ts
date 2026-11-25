import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { excerpt, matchRanges, matchTokens, merged, rowRuns, runs } from '../../src/scripts/panel/highlight.ts';
import { clipById } from './helpers.ts';

describe('matchRanges', () => {
  test('finds every place a word appears, ignoring case, diacritics and width', () => {
    assert.deepEqual(matchRanges(['cafe'], 'Café, then CAFE'), [
      { start: 0, end: 4 },
      { start: 11, end: 15 },
    ]);
    assert.deepEqual(matchRanges(['ｋｅｐｔ'], 'Kept'), [{ start: 0, end: 4 }]);
  });

  test('joins overlapping and touching places', () => {
    assert.deepEqual(matchRanges(['past', 'aste'], 'paste'), [{ start: 0, end: 5 }]);
    assert.deepEqual(matchRanges(['ab', 'cd'], 'abcd'), [{ start: 0, end: 4 }]);
    assert.deepEqual(merged([{ start: 5, end: 6 }, { start: 0, end: 2 }]), [
      { start: 0, end: 2 },
      { start: 5, end: 6 },
    ]);
  });

  test('marks the whole letter a folded match came from', () => {
    assert.deepEqual(matchRanges(['strasse'], 'Straße'), [{ start: 0, end: 6 }]);
  });

  test('marks at most 32 places per word', () => {
    assert.equal(matchRanges(['a'], 'a'.repeat(40)).length, 1, 'touching places merge');
    assert.equal(matchRanges(['a'], 'a '.repeat(40)).length, 32);
  });

  test('nothing for no words or no text', () => {
    assert.deepEqual(matchRanges([], 'text'), []);
    assert.deepEqual(matchRanges(['a'], ''), []);
  });
});

describe('excerpt', () => {
  const code = clipById('write-items').title;

  test('starts a row just before a match it would otherwise truncate, as the README screenshot shows', () => {
    assert.ok(excerpt(code, ['pasteboard']).startsWith('…[NSPasteboardItem]) -> Int {'));
  });

  test('leaves a row whose first match shows', () => {
    assert.equal(excerpt(code, ['write']), code);
    assert.equal(excerpt(code, []), code);
    assert.equal(excerpt(code, ['zzz']), code);
  });

  test('keeps eight characters before the match unless a word starts among them', () => {
    const text = 'abcdefghijklmnopqrstuvwxyz match';
    assert.equal(excerpt(text, ['match']), '…match');
    const unbroken = 'abcdefghijklmnopqrstuvwxyzmatch';
    assert.equal(excerpt(unbroken, ['match']), '…stuvwxyzmatch');
  });
});

describe('runs', () => {
  test('cuts text into matched and unmatched pieces', () => {
    assert.deepEqual(runs('git log --oneline', ['log']), [
      { text: 'git ', match: false },
      { text: 'log', match: true },
      { text: ' --oneline', match: false },
    ]);
    assert.deepEqual(runs('abc', []), [{ text: 'abc', match: false }]);
    assert.deepEqual(runs('', ['a']), []);
  });

  test('matchTokens splits the query on whitespace, as typed', () => {
    assert.deepEqual(matchTokens('  NS  board '), ['NS', 'board']);
  });
});

describe('rowRuns', () => {
  const matched = (pieces: { text: string; match: boolean }[]) =>
    pieces.filter((piece) => piece.match).map((piece) => piece.text);

  test('a link marks its host and its path apart', () => {
    const row = rowRuns(clipById('changecount'), ['apple', 'pasteboard']);
    assert.deepEqual(matched(row.primary), ['apple']);
    assert.deepEqual(matched(row.secondary), ['pasteboard']);
    assert.equal(row.primary.map((piece) => piece.text).join(''), 'developer.apple.com');
  });

  test('a named clip marks its name and its content', () => {
    const row = rowRuns(clipById('support-reply'), ['reply', 'team']);
    assert.deepEqual(matched(row.primary), ['reply']);
    assert.deepEqual(matched(row.secondary), ['team']);
  });

  test('only text rows are excerpted', () => {
    const code = rowRuns(clipById('write-items'), ['pasteboard']);
    assert.ok(code.primary[0]?.text.startsWith('…'));
    const link = rowRuns(clipById('changecount'), ['changecount']);
    assert.ok(!link.secondary[0]?.text.startsWith('…'));
  });

  test('files show their count, then their names', () => {
    const row = rowRuns(clipById('invoices'), []);
    assert.equal(row.primary[0]?.text, '3 files');
    assert.ok(row.secondary[0]?.text.startsWith('  Invoice-2041.pdf'));
  });
});
