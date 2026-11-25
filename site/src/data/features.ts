// "What Kept does" on the home page: the preview pane's fact list at reading
// size. Values use the inline convention in src/lib/inline.ts. Every claim
// comes from README.md › Features.

export interface Fact {
  label: string;
  value: string;
}

export const features: Fact[] = [
  {
    label: 'Keeps',
    value: 'What you copy: text, rich text, links, images, files and colors.',
  },
  {
    label: 'Opens',
    value:
      'Over the app you’re in when you press {⇧⌘V}, or from Kept’s icon in the menu bar. ' +
      'Kept can also run completely out of sight.',
  },
  {
    label: 'Finds',
    value:
      'Clips as you type a few letters, with the matching words set in bold. ' +
      'Filters narrow the list to pins, text, links, images or files.',
  },
  {
    label: 'Pastes',
    value:
      'Into the app you were in, with {⏎}. {⌥⏎} pastes as plain text, {⌘⏎} copies without pasting, ' +
      'and {⌘1}–{⌘9} paste the first nine clips.',
  },
  {
    label: 'Pins',
    value:
      'The clips you reuse, with {⌘P}: they stay on top and are never pruned. ' +
      'Name a clip with {⌘R} or fix its text with {⌘E}; search matches names too.',
  },
  {
    label: 'Shows',
    value:
      'Each clip as what it is: a color as its swatch, an image as a thumbnail, a file with its icon, ' +
      'a link by its host and code in monospace.',
  },
  {
    label: 'Forgets',
    value:
      'Unpinned clips you haven’t copied or pasted for a day, a week or a month, if you like. ' +
      'Pinned clips always stay.',
  },
  {
    label: 'Fits in',
    value:
      'As a native Mac app in Swift, AppKit and SwiftUI, in light and dark, ' +
      'with VoiceOver, Reduce Motion, Reduce Transparency and Increase Contrast.',
  },
];
