// The demo's history and what pins, unpins and deletes do to it, as the
// app's HistoryStore does: a new pin goes to the end of the pins; an
// unpinned clip goes back to the top of the rest, copied "now". Plus the
// list's structure: the section break under the pins and which row stays
// selected when the list changes (PanelViewModel).
import type { Clip, FilterId } from '../../data/clips.ts';
import type { Listing } from './search.ts';

export type History = Listing;

/** Rows a PgUp or PgDn moves: the rows that fit, less one (PanelController). */
export const pageSize = 10;

export function startingHistory(clips: readonly Clip[]): History {
  return { pinned: clips.filter((clip) => clip.pinned), recent: clips.filter((clip) => !clip.pinned) };
}

export function isPinned(history: History, id: string): boolean {
  return history.pinned.some((clip) => clip.id === id);
}

export function pin(history: History, id: string): History {
  const clip = history.recent.find((item) => item.id === id);
  if (!clip) return history;
  return {
    pinned: [...history.pinned, { ...clip, pinned: true }],
    recent: history.recent.filter((item) => item.id !== id),
  };
}

/** Back to the top of the history: unpinning counts as a copy now (AgeFormatter's "now", "Just now"). */
export function unpin(history: History, id: string): History {
  const clip = history.pinned.find((item) => item.id === id);
  if (!clip) return history;
  const facts = clip.facts.map((fact) => (fact.label === 'Copied' ? { ...fact, value: 'Just now' } : fact));
  return {
    pinned: history.pinned.filter((item) => item.id !== id),
    recent: [{ ...clip, pinned: false, minutesAgo: 0, age: 'now', copied: 'Just now', facts }, ...history.recent],
  };
}

export function togglePin(history: History, id: string): History {
  return isPinned(history, id) ? unpin(history, id) : pin(history, id);
}

export function remove(history: History, id: string): History {
  return {
    pinned: history.pinned.filter((clip) => clip.id !== id),
    recent: history.recent.filter((clip) => clip.id !== id),
  };
}

export function isEmpty(history: History): boolean {
  return history.pinned.length === 0 && history.recent.length === 0;
}

/** A query of only spaces isn't a search. */
export function isSearching(query: string): boolean {
  return /\S/u.test(query);
}

/** The row where unpinned clips start below the pins, when the list shows both. */
export function sectionBreak(list: readonly Clip[], query: string, filter: FilterId): number | undefined {
  if (isSearching(query) || filter === 'pinned') return undefined;
  const pins = list.findIndex((clip) => !clip.pinned);
  const count = pins === -1 ? list.length : pins;
  return count > 0 && count < list.length ? count : undefined;
}

/** After the list changed: the same clip's row, or the row that took its place, or the new last row. */
export function keptIndex(
  list: readonly Clip[],
  previousId: string | undefined,
  previousIndex: number | undefined,
): number | undefined {
  if (list.length === 0) return undefined;
  const index = list.findIndex((clip) => clip.id === previousId);
  return index !== -1 ? index : Math.min(previousIndex ?? 0, list.length - 1);
}

/** The selection moved by `offset` rows, kept inside the list. */
export function movedIndex(count: number, current: number | undefined, offset: number): number | undefined {
  if (count === 0) return undefined;
  const from = current ?? (offset > 0 ? -1 : count);
  return Math.min(Math.max(from + offset, 0), count - 1);
}
