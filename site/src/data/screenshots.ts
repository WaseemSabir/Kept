// "Screenshots" on the home page: the README's own images, with what they
// show. The structured data lists the same ones. Each PNG is 2x and carries
// the window's shadow in a transparent margin (`inset`, in CSS px) on every
// side, so it is `windowWidth + 2 × inset` CSS px wide.

import { panelDarkScreenshot, settingsScreenshot } from '../assets.ts';

export interface Screenshot {
  image: ImageMetadata;
  alt: string;
  caption: string;
  /** The window's width in CSS px. */
  windowWidth: number;
  /** The transparent margin around the window, in CSS px. */
  inset: number;
}

export const screenshots: Screenshot[] = [
  {
    image: panelDarkScreenshot,
    alt:
      'The Kept panel in dark mode while searching for “pasteboard”: two matching clips, the matched word ' +
      'set in bold, and the selected code clip previewed in full.',
    caption: 'Searching, in dark mode. The matching word is set in bold, and the preview shows the whole clip.',
    windowWidth: 720,
    inset: 20,
  },
  {
    image: settingsScreenshot,
    alt:
      'Kept’s Settings window on the General pane: open at login, show Kept in the menu bar, history size, ' +
      'pasting options and where the panel opens.',
    caption: 'Settings, on the General pane.',
    windowWidth: 560,
    inset: 20,
  },
];
