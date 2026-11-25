// /llms.txt (llmstxt.org): what Kept is, and where assistants find the rest.
import type { APIRoute } from 'astro';
import { llmsTxt } from '../lib/documents';
import { siteContext, textResponse } from '../lib/responses';

export const GET: APIRoute = async ({ site }) => textResponse(llmsTxt(await siteContext(site)), 'text/plain');
