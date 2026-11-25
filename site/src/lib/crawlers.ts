// robots.txt and sitemap.xml. Everyone may read the whole site: it's a
// product page that wants to be found, by search engines and by the AI
// assistants people ask which clipboard manager to use.

import type { Page } from '../data/pages.ts';

/**
 * AI crawlers and the fetchers assistants use when someone asks them about a
 * page. "User-agent: *" already lets them in; naming them says so on purpose,
 * for operators who only crawl where they're named.
 */
export const aiAgents = [
  // OpenAI: training, ChatGPT search, and fetches a ChatGPT user asks for.
  'GPTBot',
  'OAI-SearchBot',
  'ChatGPT-User',
  // Anthropic: training, Claude's search, and fetches a Claude user asks for.
  'ClaudeBot',
  'Claude-SearchBot',
  'Claude-User',
  // Perplexity: its index, and fetches a user asks for.
  'PerplexityBot',
  'Perplexity-User',
  // Google's and Apple's tokens for using pages in their AI models.
  'Google-Extended',
  'Applebot-Extended',
  // Common Crawl, which many models learn from.
  'CCBot',
  // Meta: training, Meta AI's search, and fetches its agents make.
  'meta-externalagent',
  'meta-webindexer',
  'meta-externalfetcher',
  // Amazon, DuckDuckGo's assistant, Mistral's Le Chat.
  'Amazonbot',
  'DuckAssistBot',
  'MistralAI-User',
] as const;

export function robotsTxt(origin: string): string {
  return [
    // ASCII only: some crawlers read robots.txt as Latin-1.
    "# Kept's website. Everything here is public and may be read, indexed and quoted,",
    '# by search engines and by AI assistants alike.',
    '',
    'User-agent: *',
    'Allow: /',
    '',
    '# AI crawlers and assistants are welcome too.',
    ...aiAgents.map((agent) => `User-agent: ${agent}`),
    'Allow: /',
    '',
    `Sitemap: ${new URL('/sitemap.xml', origin).href}`,
    '',
  ].join('\n');
}

const escapeXml = (text: string): string =>
  text.replace(/[&<>"']/g, (character) => `&${{ '&': 'amp', '<': 'lt', '>': 'gt', '"': 'quot', "'": 'apos' }[character]};`);

/**
 * The pages search engines should list, with absolute addresses. No
 * <lastmod>: the build can't tell when a page's content last changed.
 */
export function sitemapXml(origin: string, pages: readonly Page[]): string {
  const urls = pages
    .filter((page) => page.indexable)
    .map((page) => `  <url>\n    <loc>${escapeXml(new URL(page.path, origin).href)}</loc>\n  </url>`);
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    ...urls,
    '</urlset>',
    '',
  ].join('\n');
}
