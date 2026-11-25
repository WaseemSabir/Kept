// Not type-checked (no // @ts-check): checking `process` and `node:url`
// would need @types/node, and the site keeps to astro + TypeScript.
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'astro/config';
import { productionUrl } from './src/config.ts';

/** The repository root: the site reads the screenshots, the icon and Info.plist from it. */
const repoRoot = fileURLToPath(new URL('..', import.meta.url));

export default defineConfig({
  // Preview deployments can pass their own address.
  site: process.env.SITE_URL ?? productionUrl,
  output: 'static',
  trailingSlash: 'never',
  build: {
    // /shortcuts is written as shortcuts.html; the host serves clean URLs.
    format: 'file',
    // Every stylesheet is a file: the Content-Security-Policy (vercel.json)
    // allows no inline <style>, and the files are cached for good.
    inlineStylesheets: 'never',
  },
  devToolbar: { enabled: false },
  vite: {
    server: {
      fs: {
        // Images and the icon are imported from ../docs and ../Resources
        // rather than copied, so there is one file to update.
        allow: [repoRoot],
      },
    },
  },
});
