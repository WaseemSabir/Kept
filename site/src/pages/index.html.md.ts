// /index.html.md: the home page as Markdown (llmstxt.org's name for the
// twin of a page whose address has no file name).
import type { APIRoute } from 'astro';
import { homeMarkdown } from '../lib/documents';
import { screenshotImages } from '../lib/images';
import { siteContext, textResponse } from '../lib/responses';

export const GET: APIRoute = async ({ site }) => {
  const context = await siteContext(site);
  return textResponse(homeMarkdown(context, await screenshotImages(context.origin)), 'text/markdown');
};
