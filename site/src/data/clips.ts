// The live panel's clip history: the same samples as the app's snapshot
// renders (Sources/Kept/Snapshots/SampleHistory.swift), in the order the
// panel lists them (pins first, then newest first). Titles and facts follow
// the app's rules (ClipBuilder, ClipDisplay, ClipFacts), worked out below
// from each clip's content rather than typed by hand.
//
// Ages are fixed labels, as AgeFormatter would write them for the "now" of
// the README screenshots: Thursday, November 19, 2:14 AM.

export type ClipKind = 'text' | 'richText' | 'link' | 'color' | 'image' | 'file';

/** One line of the preview's fact list. */
export interface ClipFact {
  label: string;
  value: string;
  /** Cut a long value at its end ("Content") rather than its middle. */
  truncatesTail?: boolean;
}

export interface Clip {
  /** Stable, for DOM ids (`clip-<id>`, `preview-<id>`) and scripts. */
  id: string;
  kind: ClipKind;
  /** Text that looks like code, set in monospace (CodeDetector). */
  code: boolean;
  /** The generated one-line title: what the row shows when the clip has no name. */
  title: string;
  /** A name given with ⌘R; the row shows it, then the title muted. */
  name?: string;
  /** The app it was copied from, by name (no icons: they're other people's artwork). */
  source: string;
  /** The row's short age: "2m", "Yesterday", "Nov 10". */
  age: string;
  /** The preview's "Copied" fact: "26 minutes ago". */
  copied: string;
  /** How long ago it was last copied, as in SampleHistory.swift: search ranks equal matches newest first. */
  minutesAgo: number;
  pinned: boolean;
  /** Times copied; more than one shows as a fact. */
  copies: number;
  /** The whole clip as text: what a paste puts where you were typing. */
  content: string;
  /** Colors: uppercase #RRGGBB, or #RRGGBBAA when not opaque. */
  hex?: string;
  /** Images: size in pixels. The only image is the dusk landscape. */
  image?: { width: number; height: number };
  /** Files: full paths. */
  files?: string[];
  /** The preview's facts, in the app's order. */
  facts: ClipFact[];
}

/** The type filters at the end of the search bar (ClipFilter). */
export const filters = [
  { id: 'all', title: 'All', includes: () => true },
  { id: 'pinned', title: 'Pinned', includes: (clip: Clip) => clip.pinned },
  {
    id: 'text',
    title: 'Text',
    includes: (clip: Clip) => clip.kind === 'text' || clip.kind === 'richText' || clip.kind === 'color',
  },
  { id: 'links', title: 'Links', includes: (clip: Clip) => clip.kind === 'link' },
  { id: 'images', title: 'Images', includes: (clip: Clip) => clip.kind === 'image' },
  { id: 'files', title: 'Files', includes: (clip: Clip) => clip.kind === 'file' },
] as const;

export type FilterId = (typeof filters)[number]['id'];

/** The clip the panel opens with selected, as in the README. */
export const initialSelection = 'landscape';

// MARK: Samples

type Sample = Pick<Clip, 'id' | 'source' | 'age' | 'copied' | 'minutesAgo'> & {
  copies?: number;
  pinned?: boolean;
  name?: string;
} & (
    | { kind: 'text' | 'richText'; text: string; code?: boolean }
    | { kind: 'link'; url: string }
    | { kind: 'color'; text: string; hex: string }
    | { kind: 'image'; width: number; height: number; byteSize: string; format: string }
    | { kind: 'file'; paths: string[] }
  );

const samples: Sample[] = [
  // Pinned, in pin order.
  {
    id: 'ferry',
    kind: 'text',
    text: '1 Ferry Building, San Francisco, CA 94111',
    source: 'Maps',
    age: 'Nov 10',
    copied: 'Nov 10 at 2:14 AM',
    minutesAgo: 60 * 24 * 9,
    copies: 6,
    pinned: true,
  },
  {
    id: 'support-reply',
    kind: 'text',
    text: 'Thanks for reaching out! I’ve passed this along to the team, and we’ll get back to you within one business day.',
    source: 'Mail',
    age: 'Mon',
    copied: 'Monday at 2:14 AM',
    minutesAgo: 60 * 24 * 3,
    copies: 14,
    pinned: true,
    name: 'Support reply',
  },
  // Newest first.
  {
    id: 'turnaround',
    kind: 'text',
    text:
      'Thanks for the quick turnaround on the onboarding flow. Two small notes before we ship: ' +
      'the empty state should say what to do next, and the shortcut hints need to match the menu.',
    source: 'Mail',
    age: '2m',
    copied: '2 minutes ago',
    minutesAgo: 2,
  },
  {
    id: 'changecount',
    kind: 'link',
    url: 'https://developer.apple.com/documentation/appkit/nspasteboard/changecount',
    source: 'Safari',
    age: '9m',
    copied: '9 minutes ago',
    minutesAgo: 9,
    copies: 2,
  },
  {
    id: 'landscape',
    kind: 'image',
    width: 1440,
    height: 900,
    byteSize: '150 kB',
    format: 'PNG',
    source: 'Preview',
    age: '26m',
    copied: '26 minutes ago',
    minutesAgo: 26,
  },
  {
    id: 'write-items',
    kind: 'text',
    code: true,
    text: [
      'func write(_ items: [NSPasteboardItem]) -> Int {',
      '    pasteboard.clearContents()',
      '    pasteboard.writeObjects(items)',
      '    return pasteboard.changeCount',
      '}',
    ].join('\n'),
    source: 'Xcode',
    age: '1h',
    copied: 'Today at 1:10 AM',
    minutesAgo: 64,
  },
  {
    id: 'orange',
    kind: 'color',
    text: '#FF6A00',
    hex: '#FF6A00',
    source: 'Digital Color Meter',
    age: '2h',
    copied: 'Today at 12:03 AM',
    minutesAgo: 131,
  },
  {
    id: 'invoices',
    kind: 'file',
    paths: [
      '/Users/sam/Documents/Invoices/Invoice-2041.pdf',
      '/Users/sam/Documents/Invoices/Invoice-2042.pdf',
      '/Users/sam/Documents/Invoices/Receipts October.zip',
    ],
    source: 'Finder',
    age: '4h',
    copied: 'Yesterday at 10:02 PM',
    minutesAgo: 252,
  },
  {
    id: 'git-log',
    kind: 'text',
    text: 'git log --oneline --graph --decorate -20',
    source: 'Terminal',
    age: 'Yesterday',
    copied: 'Yesterday at 4:14 AM',
    minutesAgo: 60 * 22,
  },
  {
    id: 'framed-print',
    kind: 'richText',
    text: 'Pick up the framed print from the shop on Fifth before 6 pm, then drop the keys at Maya’s.',
    source: 'Notes',
    age: 'Tue',
    copied: 'Tuesday at 11:14 PM',
    minutesAgo: 60 * 27,
  },
  {
    id: 'keyboardshortcuts',
    kind: 'link',
    url: 'https://github.com/sindresorhus/KeyboardShortcuts#readme',
    source: 'Safari',
    age: 'Tue',
    copied: 'Tuesday at 1:34 AM',
    minutesAgo: 60 * 24 * 2 + 40,
  },
  {
    id: 'panel-review',
    kind: 'file',
    paths: ['/Users/sam/Desktop/Panel review.key'],
    source: 'Finder',
    age: 'Sun',
    copied: 'Sunday at 2:14 AM',
    minutesAgo: 60 * 24 * 4,
  },
  {
    id: 'invoice-json',
    kind: 'text',
    code: true,
    text: '{"id": 2041, "status": "paid", "total": 129.00, "currency": "EUR"}',
    source: 'Terminal',
    age: 'Fri',
    copied: 'Friday at 2:14 AM',
    minutesAgo: 60 * 24 * 6,
  },
  {
    id: 'blue',
    kind: 'color',
    text: 'rgba(52, 120, 246, 0.5)',
    hex: '#3478F680',
    source: 'Safari',
    age: 'Nov 7',
    copied: 'Nov 7 at 2:14 AM',
    minutesAgo: 60 * 24 * 12,
  },
  {
    id: 'sam-rivera',
    kind: 'text',
    text: 'Sam Rivera, Product Design',
    source: 'Contacts',
    age: 'Oct 31',
    copied: 'Oct 31 at 2:14 AM',
    minutesAgo: 60 * 24 * 19,
  },
];

// MARK: Building

/** Characters as people count them (the samples have no combining marks). */
const characters = (text: string): number => [...text].length;

/** "1 character", "1,204 characters". */
const count = (value: number, singular: string, plural: string): string =>
  `${value.toLocaleString('en-US')} ${value === 1 ? singular : plural}`;

/** Every run of whitespace becomes one space (TextSanitizer.singleLine). */
const singleLine = (text: string): string => text.replace(/\s+/g, ' ').trim();

const fileName = (path: string): string => path.split('/').pop() ?? path;

/** Red, green, blue and alpha (0–255) from #RRGGBB or #RRGGBBAA. */
export function rgba(hex: string): [number, number, number, number] {
  const digits = hex.replace('#', '');
  const channel = (index: number) => parseInt(digits.slice(index * 2, index * 2 + 2), 16);
  return [channel(0), channel(1), channel(2), digits.length === 8 ? channel(3) : 255];
}

function build(sample: Sample): Clip {
  const copies = sample.copies ?? 1;
  const base = {
    id: sample.id,
    source: sample.source,
    age: sample.age,
    copied: sample.copied,
    minutesAgo: sample.minutesAgo,
    pinned: sample.pinned ?? false,
    copies,
    name: sample.name,
  };
  const facts: ClipFact[] = [
    { label: 'From', value: sample.source },
    { label: 'Copied', value: sample.copied },
  ];
  if (copies > 1) facts.push({ label: 'Times copied', value: copies.toLocaleString('en-US') });

  let clip: Omit<Clip, 'facts'>;
  switch (sample.kind) {
    case 'text':
    case 'richText': {
      const lines = sample.text.split('\n').length;
      facts.push({ label: 'Size', value: count(characters(sample.text), 'character', 'characters') });
      if (lines > 1) facts.push({ label: 'Lines', value: lines.toLocaleString('en-US') });
      if (sample.kind === 'richText') facts.push({ label: 'Format', value: 'Rich text' });
      clip = { ...base, kind: sample.kind, code: sample.code ?? false, title: singleLine(sample.text), content: sample.text };
      break;
    }
    case 'link':
      facts.push({ label: 'Size', value: count(characters(sample.url), 'character', 'characters') });
      clip = { ...base, kind: 'link', code: false, title: sample.url, content: sample.url };
      break;
    case 'color': {
      const [red, green, blue, alpha] = rgba(sample.hex);
      facts.push({ label: 'RGB', value: `${red}, ${green}, ${blue}` });
      if (alpha < 255) facts.push({ label: 'Opacity', value: `${Math.round((alpha / 255) * 100)}%` });
      clip = { ...base, kind: 'color', code: true, title: sample.text, content: sample.text, hex: sample.hex };
      break;
    }
    case 'image': {
      const title = `Image ${sample.width} × ${sample.height}`;
      facts.push(
        { label: 'Dimensions', value: `${sample.width} × ${sample.height}` },
        { label: 'Size', value: sample.byteSize },
        { label: 'Format', value: sample.format },
      );
      clip = {
        ...base,
        kind: 'image',
        code: false,
        title,
        content: title,
        image: { width: sample.width, height: sample.height },
      };
      break;
    }
    case 'file':
      if (sample.paths.length > 1) facts.push({ label: 'Files', value: sample.paths.length.toLocaleString('en-US') });
      clip = {
        ...base,
        kind: 'file',
        code: false,
        title: sample.paths.map(fileName).join(', '),
        content: sample.paths.join('\n'),
        files: sample.paths,
      };
      break;
  }
  if (clip.name) {
    // The first line of what the clip holds.
    const first = clip.content.split('\n').find((line) => line.trim() !== '')?.trim() ?? clip.title;
    if (first !== clip.name) facts.push({ label: 'Content', value: first, truncatesTail: true });
  }
  return { ...clip, facts };
}

export const clips: Clip[] = samples.map(build);

// MARK: Display

/** A link split for display: host in ink, the rest muted (ClipDisplay.linkParts). */
export function linkParts(url: string): { host: string; rest: string } {
  const bare = url.replace(/^https?:\/\//i, '').replace(/^www\./i, '');
  const end = bare.search(/[/?#]/);
  if (end === -1) return { host: bare, rest: '' };
  const rest = bare.slice(end);
  return { host: bare.slice(0, end), rest: rest === '/' ? '' : rest };
}

/** A path with the home folder as `~` (ClipDisplay.abbreviatedPath). */
export function abbreviatedPath(path: string): string {
  const parts = path.split('/');
  return parts.length > 3 && parts[0] === '' && parts[1] === 'Users' ? `~/${parts.slice(3).join('/')}` : path;
}

/** The folder holding `path`, abbreviated. */
export const folderOf = (path: string): string => abbreviatedPath(path.slice(0, path.lastIndexOf('/')));

/** What the row shows: one or two tones of text (name and content, host and path, count and names). */
export function rowText(clip: Clip): { primary: string; secondary: string } {
  if (clip.name) return { primary: clip.name, secondary: `  ${clip.title}` };
  switch (clip.kind) {
    case 'link': {
      const { host, rest } = linkParts(clip.title);
      return { primary: host, secondary: rest };
    }
    case 'file': {
      const files = clip.files?.length ?? 1;
      return files > 1 ? { primary: `${files} files`, secondary: `  ${clip.title}` } : { primary: clip.title, secondary: '' };
    }
    default:
      return { primary: clip.title, secondary: '' };
  }
}

/** What VoiceOver says for the row (ClipAccessibility): kind, title, when, where from, pinned. */
export function accessibleLabel(clip: Clip): string {
  const kind = {
    text: clip.code ? 'Code' : 'Text',
    richText: clip.code ? 'Code' : 'Formatted text',
    link: 'Link',
    color: 'Color',
    image: 'Image',
    file: (clip.files?.length ?? 1) > 1 ? `${clip.files?.length} files` : 'File',
  }[clip.kind];
  let title = clip.name ?? clip.title;
  if (!clip.name && clip.kind === 'image') title = title.replace(/^Image\s*/, '');
  if (title.length > 120) title = `${title.slice(0, 120)}…`;
  const parts = [kind, title, clip.copied, `from ${clip.source}`];
  if (clip.pinned) parts.push('pinned');
  return parts.join(', ');
}
