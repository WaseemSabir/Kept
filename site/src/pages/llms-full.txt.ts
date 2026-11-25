// /llms-full.txt: the whole site as one Markdown document.
import type { APIRoute } from 'astro';
import { llmsFullTxt } from '../lib/documents';
import { siteContext, textResponse } from '../lib/responses';

export const GET: APIRoute = async ({ site }) => textResponse(llmsFullTxt(await siteContext(site)), 'text/plain');
