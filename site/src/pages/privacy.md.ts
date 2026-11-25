// /privacy.md: /privacy as Markdown.
import type { APIRoute } from 'astro';
import { privacyMarkdown } from '../lib/documents';
import { siteContext, textResponse } from '../lib/responses';

export const GET: APIRoute = async ({ site }) =>
  textResponse(privacyMarkdown(await siteContext(site)), 'text/markdown');
