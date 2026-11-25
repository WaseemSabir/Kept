// Installing Kept, from README.md › Install. Steps are a real sequence, so
// they're numbered. Strings use the inline convention in src/lib/inline.ts.

import { latestReleaseUrl, minimumMacOS } from '../config.ts';
import type { Release } from './release.ts';

export const requirement = `Kept needs macOS ${minimumMacOS.version} ${minimumMacOS.name} or later.`;

export function installSteps(release: Release): string[] {
  const diskImage = release.fileName ?? `Kept-${release.version ?? '<version>'}.dmg`;
  return [
    `Download the disk image, \`${diskImage}\`, from the [latest release](${latestReleaseUrl}).`,
    'Open it and drag Kept to Applications.',
    'Open Kept. A short welcome tells you where it is: in the menu bar, and on {⇧⌘V}.',
    'Press {⇧⌘V} in any app to see what you’ve copied, and {⏎} to paste it.',
  ];
}

export interface InstallNote {
  id: string;
  title: string;
  paragraphs: string[];
}

export const installNotes: InstallNote[] = [
  {
    id: 'if-not-opened',
    title: 'If macOS says “Kept” Not Opened',
    paragraphs: [
      'Releases aren’t notarized by Apple yet, so macOS stops the first launch. On macOS 15 and later, ' +
        'click **Done**, then **Open Anyway** in System Settings › Privacy & Security (under Security). ' +
        'On macOS 14, Control-click Kept and choose **Open**.',
      'Or run `xattr -dr com.apple.quarantine /Applications/Kept.app` in Terminal.',
    ],
  },
  {
    id: 'paste-permission',
    title: 'Pasting for you needs your permission',
    paragraphs: [
      'Kept pastes by pressing {⌘V} in the app you were using, which macOS allows only once you turn Kept ' +
        'on in System Settings › Privacy & Security (under Accessibility up to macOS 26). Kept asks the ' +
        'first time you paste; until then it copies the clip and you press {⌘V} yourself.',
      'Releases without a Developer ID signature lose this permission with each update: remove Kept from ' +
        'the list and add it again.',
    ],
  },
];
