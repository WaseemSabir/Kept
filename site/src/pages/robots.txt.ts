// /robots.txt: everyone may read everything; the sitemap lists the pages.
import type { APIRoute } from 'astro';
import { robotsTxt } from '../lib/crawlers';
import { requireSite, textResponse } from '../lib/responses';

export const GET: APIRoute = ({ site }) => textResponse(robotsTxt(requireSite(site).origin), 'text/plain');
