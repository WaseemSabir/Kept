// /sitemap.xml: the pages search engines should list (src/data/pages.ts).
import type { APIRoute } from 'astro';
import { indexedPages } from '../data/pages';
import { sitemapXml } from '../lib/crawlers';
import { requireSite, textResponse } from '../lib/responses';

export const GET: APIRoute = ({ site }) =>
  textResponse(sitemapXml(requireSite(site).origin, indexedPages), 'application/xml');
