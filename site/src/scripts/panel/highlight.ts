// Where the query's words appear in a row's text, so the row can set them
// semibold: MatchHighlighter, ported. For display only; matching and ranking
// are search.ts. Like the search it ignores case, diacritics and width, so
// "cafe" marks "Café".
import { rowText, type Clip } from '../../data/clips.ts';
import { fold, foldWithMap } from './fold.ts';

/** At most this many places are marked per word. */
export const maxMatchesPerToken = 32;
/** About how many characters of a title a row shows before it truncates. */
export const visiblePrefix = 20;
/** How much of what comes before the first match an excerpt keeps. */
export const leadingContext = 8;

/** A span of the original text, in UTF-16 offsets. */
export interface TextRange {
  start: number;
  end: number;
}

/** A piece of text and whether it matched. */
export interface Run {
  text: string;
  match: boolean;
}

/** The query's words, split on whitespace. */
export function matchTokens(query: string): string[] {
  return query.split(/\s+/u).filter((word) => word !== '');
}

/** `ranges` in order, with overlapping or touching ones joined. */
export function merged(ranges: readonly TextRange[]): TextRange[] {
  const result: TextRange[] = [];
  for (const range of [...ranges].sort((a, b) => a.start - b.start)) {
    const last = result.at(-1);
    if (last && range.start <= last.end) last.end = Math.max(last.end, range.end);
    else result.push({ ...range });
  }
  return result;
}

/** Every place a token appears in `text`, in order, merged. */
export function matchRanges(tokens: readonly string[], text: string): TextRange[] {
  if (text === '') return [];
  const folded = foldWithMap(text);
  const found: TextRange[] = [];
  for (const token of tokens) {
    const needle = fold(token);
    if (needle === '') continue;
    let from = 0;
    for (let count = 0; count < maxMatchesPerToken; count += 1) {
      const at = folded.text.indexOf(needle, from);
      if (at === -1) break;
      found.push({ start: folded.starts[at] ?? 0, end: folded.ends[at + needle.length - 1] ?? text.length });
      from = at + needle.length;
    }
  }
  return merged(found);
}

/** `index` moved back by `count` characters (code points), not past the start. */
function backBy(text: string, index: number, count: number): number {
  let at = index;
  for (let step = 0; step < count && at > 0; step += 1) {
    const low = text.charCodeAt(at - 1);
    at -= low >= 0xdc00 && low <= 0xdfff && at > 1 ? 2 : 1;
  }
  return at;
}

/**
 * `text` from just before its first match, after "…", when that match would
 * otherwise fall where the row truncates; otherwise `text`. The excerpt
 * starts at a word when one begins shortly before the match.
 */
export function excerpt(text: string, tokens: readonly string[]): string {
  const first = matchRanges(tokens, text)[0];
  if (!first || [...text.slice(0, first.start)].length <= visiblePrefix) return text;
  let start = backBy(text, first.start, leadingContext);
  const space = text.slice(start, first.start).search(/\s/u);
  if (space !== -1) start += space + 1;
  return `…${text.slice(start)}`;
}

/** `text` cut into runs, each saying whether it matched. */
export function runs(text: string, tokens: readonly string[]): Run[] {
  const ranges = matchRanges(tokens, text);
  if (ranges.length === 0) return text === '' ? [] : [{ text, match: false }];
  const result: Run[] = [];
  let cursor = 0;
  for (const range of ranges) {
    if (cursor < range.start) result.push({ text: text.slice(cursor, range.start), match: false });
    result.push({ text: text.slice(range.start, range.end), match: true });
    cursor = range.end;
  }
  if (cursor < text.length) result.push({ text: text.slice(cursor), match: false });
  return result;
}

/**
 * A row's two tones of text (rowText), with the matches marked. A text row
 * whose first match would be truncated starts just before it (ClipSummary).
 */
export function rowRuns(clip: Clip, tokens: readonly string[]): { primary: Run[]; secondary: Run[] } {
  const { primary, secondary } = rowText(clip);
  const excerpted = !clip.name && (clip.kind === 'text' || clip.kind === 'richText');
  return {
    primary: runs(excerpted ? excerpt(primary, tokens) : primary, tokens),
    secondary: runs(secondary, tokens),
  };
}
