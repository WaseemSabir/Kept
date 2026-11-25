// What the site's non-HTML endpoints (src/pages/*.ts) share. The build
// writes their bodies to dist/ as files; the Content-Type here is what
// `astro dev` serves. In production vercel.json sets it per extension.

import type { Release } from '../data/release';
import { getRelease } from '../data/release';
import type { SiteContext } from './documents';

export type TextType = 'text/plain' | 'text/markdown' | 'application/xml' | 'application/manifest+json';

export function textResponse(body: string, type: TextType): Response {
  return new Response(body, { headers: { 'Content-Type': `${type}; charset=utf-8` } });
}

/** The site's address from astro.config.mjs; endpoints write absolute links with it. */
export function requireSite(site: URL | undefined): URL {
  if (!site) throw new Error('Set `site` in astro.config.mjs: the site writes absolute links.');
  return site;
}

export async function siteContext(site: URL | undefined): Promise<SiteContext> {
  const release: Release = await getRelease();
  return { origin: requireSite(site).origin, release };
}
