// /shortcuts.md: /shortcuts as Markdown.
import type { APIRoute } from 'astro';
import { shortcutsMarkdown } from '../lib/documents';
import { siteContext, textResponse } from '../lib/responses';

export const GET: APIRoute = async ({ site }) =>
  textResponse(shortcutsMarkdown(await siteContext(site)), 'text/markdown');
