// What the panel says, in the app's words: the empty states
// (PanelViewModel+Display), the footer's hints (PanelFooter), what a screen
// reader hears, and what a paste puts on the line under the panel.
import type { Clip, FilterId } from '../../data/clips.ts';
import { isEmpty, isSearching, type History } from './history.ts';

export interface EmptyState {
  title: string;
  hint?: string;
  /** The message takes the whole panel (there's nothing to preview) rather than the list's column. */
  spansPanel: boolean;
}

/** What the filter's clips are called (ClipDisplay.noun), singular and plural. */
const nouns: Record<FilterId, [string, string]> = {
  all: ['clip', 'clips'],
  pinned: ['pinned clip', 'pinned clips'],
  text: ['text clip', 'text clips'],
  links: ['link', 'links'],
  images: ['image', 'images'],
  files: ['file', 'files'],
};

/** At most 40 characters of the query, then "…". */
function shortened(text: string, limit = 40): string {
  const characters = [...text];
  return characters.length > limit ? `${characters.slice(0, limit).join('')}…` : text;
}

/**
 * What to say when the list is empty. The app adds "or Tab to look in other
 * kinds" while a filter is on; on the page Tab moves on through the page, so
 * the hint stops at Esc.
 */
export function emptyState(history: History, query: string, filter: FilterId): EmptyState {
  if (isEmpty(history)) {
    return {
      title: 'Copy something and it shows up here.',
      hint: 'Text, links, images and files you copy are kept here. Pin the ones you use often with ⌘P.',
      spansPanel: true,
    };
  }
  if (isSearching(query)) {
    return {
      title: `No ${nouns[filter][1]} match “${shortened(query.trim())}”.`,
      hint: 'Press Esc to clear the search.',
      spansPanel: false,
    };
  }
  switch (filter) {
    case 'all':
      return { title: 'Nothing to show.', spansPanel: false };
    case 'pinned':
      return {
        title: 'No pinned clips yet.',
        hint: 'Select a clip and press ⌘P to keep it at the top.',
        spansPanel: false,
      };
    case 'text':
      return { title: 'No text clips yet.', hint: 'Text you copy shows up here.', spansPanel: false };
    case 'links':
      return { title: 'No links yet.', hint: 'Links you copy show up here.', spansPanel: false };
    case 'images':
      return {
        title: 'No images yet.',
        hint: 'Copy an image, or press ⌃⇧⌘4 to copy part of the screen.',
        spansPanel: false,
      };
    case 'files':
      return { title: 'No files yet.', hint: 'Copy files in Finder and they show up here.', spansPanel: false };
  }
}

/** The footer's hints for now: the clip actions while a clip is selected, else what Esc does. */
export interface FooterHints {
  /** ⏎, ⌥⏎, ⌘⏎ and ⌘P. */
  actions: boolean;
  pin: 'Pin' | 'Unpin';
  /** ⌘⌫ deletes only while the search is empty; with a query it edits the search. */
  delete: boolean;
  esc?: 'Clear search' | 'Close';
}

export function footerHints(selected: Clip | undefined, query: string): FooterHints {
  if (selected) return { actions: true, pin: selected.pinned ? 'Unpin' : 'Pin', delete: query === '' };
  return { actions: false, pin: 'Pin', delete: false, esc: isSearching(query) ? 'Clear search' : 'Close' };
}

/** What a screen reader hears; the copy-only line is PasteHintCopy.spokenTitle. */
export const spoken = {
  pinned: 'Pinned.',
  unpinned: 'Unpinned.',
  deleted: 'Deleted.',
  pasted: 'Pasted.',
  pastedPlain: 'Pasted as plain text.',
  copied: 'Copied. Press Command V to paste.',
  reset: 'History reset.',
} as const;

/** "15 clips.", "1 link.": what the list holds after a search or a filter. */
export function resultsPhrase(count: number, filter: FilterId): string {
  const [one, many] = nouns[filter];
  return `${count.toLocaleString('en-US')} ${count === 1 ? one : many}.`;
}

/** What a paste puts where you were typing. */
export type Pasted =
  | { kind: 'text'; text: string; code: boolean; link: boolean }
  | { kind: 'image'; label: string };

/**
 * Text as text, code in monospace, a link as its address, a color as its
 * value, files as their names, the image as a picture. Plain text drops the
 * formatting; an image has no text, so it pastes whole either way, as in
 * the app.
 */
export function pasted(clip: Clip, plain: boolean): Pasted {
  switch (clip.kind) {
    case 'image':
      return { kind: 'image', label: clip.title };
    case 'file': {
      const names = (clip.files ?? []).map((path) => path.split('/').pop() ?? path);
      return { kind: 'text', text: names.join('\n'), code: false, link: false };
    }
    case 'link':
      return { kind: 'text', text: clip.content, code: false, link: !plain };
    default:
      return { kind: 'text', text: clip.content, code: clip.code && !plain, link: false };
  }
}
