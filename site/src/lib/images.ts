// The home page's screenshots as files with absolute addresses, for the
// structured data and the Markdown twin: each at its full 2x size, as WebP
// (a fraction of the PNG's weight; search engines and assistants read it).

import { getImage } from 'astro:assets';
import { screenshots } from '../data/screenshots';

export interface ScreenshotImage {
  url: string;
  width: number;
  height: number;
  alt: string;
  caption: string;
}

export async function screenshotImages(origin: string): Promise<ScreenshotImage[]> {
  return Promise.all(
    screenshots.map(async (shot) => {
      const image = await getImage({ src: shot.image, format: 'webp' });
      return {
        url: new URL(image.src, origin).href,
        width: shot.image.width,
        height: shot.image.height,
        alt: shot.alt,
        caption: shot.caption,
      };
    }),
  );
}
