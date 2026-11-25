// /manifest.webmanifest: the name, icons and colors browsers use when the
// site is saved to a home screen or dock. It stays a web page
// (display: browser); Kept itself is the Mac app.
import type { APIRoute } from 'astro';
import { language, name, pageColor } from '../config';
import { home } from '../data/pages';
import { textResponse } from '../lib/responses';

export const GET: APIRoute = () =>
  textResponse(
    `${JSON.stringify(
      {
        id: '/',
        name,
        short_name: name,
        description: home.description,
        lang: language,
        start_url: '/',
        scope: '/',
        display: 'browser',
        background_color: pageColor.light,
        theme_color: pageColor.light,
        icons: [
          { src: '/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
          { src: '/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          { src: '/icon-maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      null,
      2,
    )}\n`,
    'application/manifest+json',
  );
