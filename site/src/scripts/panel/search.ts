// What the panel lists for a query and a type filter: ClipSearch, ported.
//
// Matching is case-, diacritic- and width-insensitive and every
// whitespace-separated word must match. Each word scores by its best match:
// at the start of a word (3), anywhere (2), or, for words of three or more
// characters, as a subsequence near the start of the clip (1). Higher totals
// rank first; ties go to the most recently copied clip. An empty query lists
// the pins, in pin order, then the rest, newest first.
import { filters, type Clip, type FilterId } from '../../data/clips.ts';
import { fold } from './fold.ts';

/** How far into a clip's search text, in UTF-8 bytes, a subsequence match may reach. */
export const fuzzyWindow = 256;
/** Words shorter than this (as typed) never match as a subsequence. */
export const minimumFuzzyLength = 3;

export interface SearchToken {
  /** The word, folded. */
  text: string;
  allowsFuzzy: boolean;
}

/** 1 a subsequence, 2 anywhere, 3 at the start of a word. */
export type MatchQuality = 1 | 2 | 3;

/** The pinned clips in pin order, and the rest newest first. */
export interface Listing {
  readonly pinned: readonly Clip[];
  readonly recent: readonly Clip[];
}

export function searchTokens(query: string): SearchToken[] {
  return query
    .split(/\s+/u)
    .filter((word) => word !== '')
    .map((word) => ({ text: fold(word), allowsFuzzy: [...word].length >= minimumFuzzyLength }))
    .filter((token) => token.text !== '');
}

/** What a clip is searched by: its name, then its content with whitespace collapsed (Clip.searchKey). */
export function searchKey(clip: Pick<Clip, 'name' | 'content'>): string {
  const content = clip.content.replace(/\s+/gu, ' ').trim();
  return fold(clip.name ? `${clip.name}\n${content}` : content);
}

/** Whether a match right after this UTF-16 unit starts a word: anything but a–z, 0–9 and non-ASCII. */
function startsWord(code: number): boolean {
  const letterOrDigit = (code >= 0x61 && code <= 0x7a) || (code >= 0x30 && code <= 0x39);
  return !letterOrDigit && code < 0x80;
}

function utf8Length(character: string): number {
  const code = character.codePointAt(0) ?? 0;
  return code < 0x80 ? 1 : code < 0x800 ? 2 : code < 0x10000 ? 3 : 4;
}

/** Whether `needle`'s characters appear in order among those that start in the first `fuzzyWindow` bytes. */
function isSubsequence(needle: string, text: string): boolean {
  const wanted = [...needle];
  let next = 0;
  let bytes = 0;
  for (const character of text) {
    if (next === wanted.length || bytes >= fuzzyWindow) break;
    if (character === wanted[next]) next += 1;
    bytes += utf8Length(character);
  }
  return next === wanted.length;
}

export function matchQuality(token: SearchToken, key: string): MatchQuality | undefined {
  let foundAnywhere = false;
  for (let at = key.indexOf(token.text); at !== -1; at = key.indexOf(token.text, at + 1)) {
    if (at === 0 || startsWord(key.charCodeAt(at - 1))) return 3;
    foundAnywhere = true;
  }
  if (foundAnywhere) return 2;
  return token.allowsFuzzy && isSubsequence(token.text, key) ? 1 : undefined;
}

/** The summed scores of the tokens, or `undefined` when one of them doesn't match. */
export function score(key: string, tokens: readonly SearchToken[]): number | undefined {
  let total = 0;
  for (const token of tokens) {
    const quality = matchQuality(token, key);
    if (quality === undefined) return undefined;
    total += quality;
  }
  return total;
}

/** ClipFilter.includes, from the filters the search bar shows. */
export function filterIncludes(filter: FilterId): (clip: Clip) => boolean {
  const found = filters.find((item) => item.id === filter) ?? filters[0];
  return (clip) => found.includes(clip);
}

/** The clips to list for `query` and `filter`, best first. */
export function searchResults(query: string, filter: FilterId, listing: Listing): Clip[] {
  const includes = filterIncludes(filter);
  const everything = [...listing.pinned, ...listing.recent];
  const tokens = searchTokens(query);
  if (tokens.length === 0) return everything.filter(includes);

  const matches: { clip: Clip; score: number; order: number }[] = [];
  everything.forEach((clip, order) => {
    if (!includes(clip)) return;
    const total = score(searchKey(clip), tokens);
    if (total !== undefined) matches.push({ clip, score: total, order });
  });
  matches.sort((a, b) => b.score - a.score || a.clip.minutesAgo - b.clip.minutesAgo || a.order - b.order);
  return matches.map((match) => match.clip);
}
