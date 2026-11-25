// Shared by the panel's tests: the page's own history, and clips made up for a case.
import { clips, type Clip } from '../../src/data/clips.ts';

export { clips };

export function clipById(id: string): Clip {
  const clip = clips.find((item) => item.id === id);
  if (!clip) throw new Error(`No clip ${id}`);
  return clip;
}

export const ids = (list: readonly Clip[]): string[] => list.map((clip) => clip.id);

/** A text clip with what a case needs; the rest is filler. */
export function textClip(id: string, content: string, extra: Partial<Clip> = {}): Clip {
  return {
    id,
    kind: 'text',
    code: false,
    title: content.replace(/\s+/g, ' ').trim(),
    source: 'Notes',
    age: '1m',
    copied: '1 minute ago',
    minutesAgo: 1,
    pinned: false,
    copies: 1,
    content,
    facts: [{ label: 'Copied', value: '1 minute ago' }],
    ...extra,
  };
}
