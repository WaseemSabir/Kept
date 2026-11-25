import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { fold, foldWithMap } from '../../src/scripts/panel/fold.ts';
import { startingHistory } from '../../src/scripts/panel/history.ts';
import { matchQuality, searchKey, searchResults, searchTokens } from '../../src/scripts/panel/search.ts';
import { clips, ids, textClip } from './helpers.ts';

const history = startingHistory(clips);

describe('fold', () => {
  test('ignores case, diacritics and width, and spells out letters people type without marks', () => {
    assert.equal(fold('Café'), 'cafe');
    assert.equal(fold('ＫＥＰＴ'), 'kept');
    assert.equal(fold('ﬁle'), 'file');
    assert.equal(fold('Straße'), 'strasse');
    assert.equal(fold('Øresund'), 'oresund');
    assert.equal(fold('NSPasteboard'), 'nspasteboard');
  });

  test('maps each folded unit back to the character it came from', () => {
    const folded = foldWithMap('aßb');
    assert.equal(folded.text, 'assb');
    assert.deepEqual(folded.starts, [0, 1, 1, 2]);
    assert.deepEqual(folded.ends, [1, 2, 2, 3]);
  });
});

describe('searchTokens', () => {
  test('splits on whitespace, folds, and allows subsequences from three characters', () => {
    assert.deepEqual(searchTokens('  Git  LOG '), [
      { text: 'git', allowsFuzzy: true },
      { text: 'log', allowsFuzzy: true },
    ]);
    assert.deepEqual(searchTokens('fé'), [{ text: 'fe', allowsFuzzy: false }]);
    assert.deepEqual(searchTokens('   '), []);
  });
});

describe('matchQuality', () => {
  const quality = (query: string, text: string) => matchQuality(searchTokens(query)[0]!, fold(text));

  test('scores the start of a word over the middle of one over a subsequence', () => {
    assert.equal(quality('paste', 'pasteboard.clearContents()'), 3);
    assert.equal(quality('board', 'pasteboard.clearContents()'), 2);
    assert.equal(quality('clear', 'pasteboard.clearContents()'), 3, 'after a dot starts a word');
    assert.equal(quality('pbd', 'pasteboard'), 1);
    assert.equal(quality('zzz', 'pasteboard'), undefined);
  });

  test('takes the best place a word appears, not the first', () => {
    assert.equal(quality('board', 'keyboard board'), 3);
  });

  test("doesn't match short words as subsequences", () => {
    assert.equal(quality('pb', 'pasteboard'), undefined);
  });

  test('a match after a non-ASCII letter is inside a word; after punctuation it starts one', () => {
    assert.equal(quality('x', 'жx'), 2);
    assert.equal(quality('x', 'éx'), 2, 'é folds to e, a letter');
    assert.equal(quality('x', '—x'), 2, 'non-ASCII punctuation counts as a letter, as in the app');
    assert.equal(quality('x', '-x'), 3);
  });
});

describe('searchKey', () => {
  test('is the name, then the content with whitespace collapsed', () => {
    assert.equal(searchKey({ name: 'Support reply', content: 'Thanks\n\nfor  it' }), 'support reply\nthanks for it');
    assert.equal(searchKey({ content: ' a\tb ' }), 'a b');
  });
});

describe('searchResults', () => {
  test('an empty query lists the pins in pin order, then the rest newest first', () => {
    assert.deepEqual(ids(searchResults('', 'all', history)), ids(clips));
    assert.deepEqual(ids(searchResults('  ', 'all', history)), ids(clips));
  });

  test('filters by kind as ClipFilter does', () => {
    assert.deepEqual(ids(searchResults('', 'pinned', history)), ['ferry', 'support-reply']);
    assert.deepEqual(ids(searchResults('', 'links', history)), ['changecount', 'keyboardshortcuts']);
    assert.deepEqual(ids(searchResults('', 'images', history)), ['landscape']);
    assert.deepEqual(ids(searchResults('', 'files', history)), ['invoices', 'panel-review']);
    const text = ids(searchResults('', 'text', history));
    assert.ok(text.includes('orange') && text.includes('blue'), 'colors count as text');
    assert.ok(text.includes('framed-print'), 'rich text counts as text');
    assert.ok(!text.includes('changecount'));
  });

  test('"pasteboard" finds the code before the link, as in the README screenshot', () => {
    assert.deepEqual(ids(searchResults('pasteboard', 'all', history)), ['write-items', 'changecount']);
  });

  test('equal scores go to the most recently copied clip, pinned or not', () => {
    // Both start with "Thanks": the reply is pinned but was copied 3 days ago.
    // The framed print matches only as a subsequence, so it comes last.
    assert.deepEqual(ids(searchResults('thanks', 'all', history)), ['turnaround', 'support-reply', 'framed-print']);
  });

  test('matches a name, diacritics and width aside', () => {
    // First by its name; others hold s-u-p-p-o-r-t only as a subsequence.
    assert.equal(ids(searchResults('SUPPORT', 'all', history))[0], 'support-reply');
    assert.deepEqual(ids(searchResults('support reply', 'all', history)), ['support-reply', 'turnaround']);
    const listing = { pinned: [], recent: [textClip('cafe', 'Café au lait'), textClip('other', 'tea')] };
    assert.deepEqual(ids(searchResults('cafe', 'all', listing)), ['cafe']);
    assert.deepEqual(ids(searchResults('ｃａｆｅ', 'all', listing)), ['cafe']);
  });

  test('every word must match', () => {
    assert.deepEqual(ids(searchResults('git graph', 'all', history)), ['git-log']);
    assert.deepEqual(ids(searchResults('git zebra', 'all', history)), []);
  });

  test('searches file paths and keeps to the filter', () => {
    assert.deepEqual(ids(searchResults('invoices', 'files', history)), ['invoices']);
    assert.equal(ids(searchResults('paid', 'text', history))[0], 'invoice-json', 'a word start; the rest are subsequences');
    assert.deepEqual(ids(searchResults('paid', 'files', history)), ['invoices'], 'files only (p…a…i…d in the paths)');
  });

  test('nothing matches nonsense', () => {
    assert.deepEqual(searchResults('qqqqzz', 'all', history), []);
  });

  test('a subsequence only counts near the start of a clip; a substring counts anywhere', () => {
    const near = textClip('near', `a1b2c ${'x'.repeat(300)}`);
    const far = textClip('far', `${'x'.repeat(300)} a1b2c`);
    const listing = { pinned: [], recent: [near, far] };
    assert.deepEqual(ids(searchResults('abc', 'all', listing)), ['near'], 'past 256 bytes, no subsequence');
    assert.deepEqual(ids(searchResults('a1b2c', 'all', listing)), ['near', 'far']);
  });

  test('ranks a word start above a substring above a subsequence', () => {
    const listing = {
      pinned: [],
      recent: [
        textClip('sub', 'pXaXsXt', { minutesAgo: 1 }),
        textClip('mid', 'repast', { minutesAgo: 2 }),
        textClip('start', 'past due', { minutesAgo: 3 }),
      ],
    };
    assert.deepEqual(ids(searchResults('past', 'all', listing)), ['start', 'mid', 'sub']);
  });
});
