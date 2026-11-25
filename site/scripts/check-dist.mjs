#!/usr/bin/env node
// npm run check:dist: checks the built site in dist/ before anyone sees it.
// Node built-ins only; CI runs it after `npm run build` (.github/workflows/site.yml).
//
// It fails, naming the file and the reason, when:
// - an internal href/src/srcset (clean URLs: /shortcuts is shortcuts.html)
//   doesn't resolve to a file, a #fragment to an element id, or a link
//   points at an address that only redirects (/x.html, /x/);
// - a page hasn't exactly one <h1>, a unique non-empty <title> (≤ 60
//   characters) and meta description (≤ 155), or, unless it's noindex, a
//   canonical link on the site's origin that points back at itself, a
//   Markdown twin and structured data;
// - the sitemap and the indexable pages differ;
// - a JSON-LD block doesn't parse or has no @context;
// - robots.txt, sitemap.xml, llms.txt, llms-full.txt, the Markdown twins,
//   the manifest, og.png (1200 × 630) or an icon is missing or malformed,
//   or a twin has a heading its page doesn't;
// - there's an inline <style>, a style="" or on…="" attribute, an
//   executable inline <script> or a javascript: URL (the CSP blocks them);
// - a script, stylesheet, image, media or font comes from another origin;
// - vercel.json doesn't parse, or its ignoreCommand script is missing or
//   not executable.
//
// The checks are pure functions of the files, exported for tests/check-dist.test.ts.

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const limits = { title: 60, description: 155 };

/** Files every build must have, besides the pages. */
export const requiredFiles = [
  '404.html',
  'robots.txt',
  'sitemap.xml',
  'llms.txt',
  'llms-full.txt',
  'manifest.webmanifest',
  'favicon.ico',
  'favicon.svg',
];

/** PNGs and the size each must be. */
export const requiredImages = {
  'og.png': [1200, 630],
  'apple-touch-icon.png': [180, 180],
  'icon-192.png': [192, 192],
  'icon-512.png': [512, 512],
  'icon-maskable-512.png': [512, 512],
};

// MARK: Reading HTML (enough for what Astro writes)

const entities = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };

export function decodeEntities(text) {
  return text.replace(/&(#x[\da-f]+|#\d+|[a-z]+);/gi, (whole, name) => {
    if (name[0] === '#') {
      const code = name[1] === 'x' || name[1] === 'X' ? parseInt(name.slice(2), 16) : parseInt(name.slice(1), 10);
      return Number.isFinite(code) ? String.fromCodePoint(code) : whole;
    }
    return entities[name.toLowerCase()] ?? whole;
  });
}

/**
 * `a="1" b='2' c=3 d` → { a: '1', b: '2', c: '3', d: '' }, names lowercased, values decoded.
 * @param {string} source
 * @returns {Record<string, string>}
 */
export function parseAttributes(source) {
  /** @type {Record<string, string>} */
  const attributes = {};
  const pattern = /([^\s"'<>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
  for (const match of source.matchAll(pattern)) {
    const name = match[1].toLowerCase();
    if (name in attributes) continue;
    attributes[name] = decodeEntities(match[2] ?? match[3] ?? match[4] ?? '');
  }
  return attributes;
}

const rawTextElements = new Set(['script', 'style', 'title', 'textarea']);

/**
 * @typedef {object} Tag
 * @property {string} name  lowercased
 * @property {Record<string, string>} attributes
 * @property {number} start  where `<` is
 * @property {number} end  just after `>`
 * @property {string} [content]  for script, style, title and textarea: what's inside
 */

/**
 * The start tags of a document, in order, with `content` for script,
 * style, title and textarea. Comments and the insides of raw-text elements
 * are skipped, so a "<a" in a script isn't a tag.
 * @param {string} html
 * @returns {Tag[]}
 */
export function scanHtml(html) {
  const lower = html.toLowerCase();
  const tags = [];
  let index = 0;
  while (index < html.length) {
    const open = html.indexOf('<', index);
    if (open < 0) break;
    if (html.startsWith('<!--', open)) {
      const close = html.indexOf('-->', open + 4);
      index = close < 0 ? html.length : close + 3;
      continue;
    }
    const name = /^<([a-z][a-z\d-]*)/i.exec(html.slice(open, open + 64))?.[1];
    if (!name) {
      // A doctype, an end tag or a stray "<".
      const close = html.indexOf('>', open);
      index = close < 0 ? html.length : close + 1;
      continue;
    }
    let end = open + name.length + 1;
    for (let quote = ''; end < html.length; end++) {
      const character = html[end];
      if (quote) {
        if (character === quote) quote = '';
      } else if (character === '"' || character === "'") quote = character;
      else if (character === '>') break;
    }
    /** @type {Tag} */
    const tag = {
      name: name.toLowerCase(),
      attributes: parseAttributes(html.slice(open + name.length + 1, end)),
      start: open,
      end: end + 1,
    };
    tags.push(tag);
    index = end + 1;
    if (rawTextElements.has(tag.name)) {
      const close = lower.indexOf(`</${tag.name}`, index);
      tag.content = html.slice(index, close < 0 ? html.length : close);
      index = close < 0 ? html.length : close;
    }
  }
  return tags;
}

/**
 * The text inside an element: tags dropped, entities decoded, white space collapsed.
 * @param {string} html
 * @param {Tag} tag
 */
export function textOf(html, tag) {
  const close = html.toLowerCase().indexOf(`</${tag.name}`, tag.end);
  const inner = html.slice(tag.end, close < 0 ? html.length : close);
  return decodeEntities(inner.replace(/<[^>]*>/g, '')).replace(/\s+/g, ' ').trim();
}

/** A srcset's URLs. */
export function srcsetUrls(srcset) {
  return srcset
    .split(',')
    .map((candidate) => candidate.trim().split(/\s+/)[0])
    .filter(Boolean);
}

/** Script types a browser runs (an absent type is JavaScript). Anything else is data. */
export function isExecutableScript(attributes) {
  const type = (attributes.type ?? '').trim().toLowerCase();
  return (
    type === '' ||
    type === 'module' ||
    type === 'importmap' ||
    type === 'speculationrules' ||
    /^(text|application)\/(x-)?(java|ecma)script$/.test(type)
  );
}

// MARK: Binary formats

/** A PNG's width and height from its IHDR chunk, or undefined if it isn't a PNG. */
export function pngSize(bytes) {
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length < 24 || signature.some((byte, index) => bytes[index] !== byte)) return undefined;
  if (String.fromCharCode(...bytes.slice(12, 16)) !== 'IHDR') return undefined;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return [view.getUint32(16), view.getUint32(20)];
}

/** The square sizes in an ICO file, or undefined if it isn't one. */
export function icoSizes(bytes) {
  if (bytes.length < 6) return undefined;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  if (view.getUint16(0, true) !== 0 || view.getUint16(2, true) !== 1) return undefined;
  const count = view.getUint16(4, true);
  if (count === 0 || bytes.length < 6 + 16 * count) return undefined;
  return Array.from({ length: count }, (_, index) => bytes[6 + 16 * index] || 256);
}

// MARK: Addresses

/**
 * The dist/ file a path is served from, as the host serves it (cleanUrls):
 * "/" → index.html, "/shortcuts" → shortcuts.html, "/favicon.svg" as is.
 */
export function fileForPath(pathname, files) {
  let path;
  try {
    path = decodeURIComponent(pathname).replace(/^\/+/, '');
  } catch {
    return undefined;
  }
  if (path === '') return files.has('index.html') ? 'index.html' : undefined;
  for (const candidate of [path, `${path}.html`, `${path.replace(/\/$/, '')}/index.html`]) {
    if (files.has(candidate)) return candidate;
  }
  return undefined;
}

/** The address a dist/ HTML file is served at: index.html → "/", shortcuts.html → "/shortcuts". */
export function pathForFile(file) {
  if (file === 'index.html') return '/';
  return `/${file.replace(/(^|\/)index\.html$/, '$1').replace(/\.html$/, '').replace(/\/$/, '')}`;
}

/** Content-Security-Policy directives from vercel.json's headers, for the paths it covers. */
export function cspDirectives(vercel) {
  for (const rule of vercel?.headers ?? []) {
    for (const header of rule.headers ?? []) {
      if (header.key?.toLowerCase() === 'content-security-policy') {
        return Object.fromEntries(
          header.value
            .split(';')
            .map((directive) => directive.trim().split(/\s+/))
            .filter(([name]) => name)
            .map(([name, ...values]) => [name.toLowerCase(), values]),
        );
      }
    }
  }
  return undefined;
}

// MARK: The checks

const decoder = new TextDecoder('utf-8', { fatal: true });

/**
 * Every problem with a built site, as { file, reason }.
 *
 * files         Map of dist/-relative paths ("index.html", "_astro/a.css") to bytes
 * origin        the site's address, "https://kept.waseemsabir.com"
 * vercel        vercel.json, parsed, or an Error if it doesn't parse
 * isExecutable  (path relative to the site directory) → whether that file exists and is executable
 *
 * @param {{
 *   files: Map<string, Uint8Array>,
 *   origin: string,
 *   vercel?: any,
 *   isExecutable?: (path: string) => boolean,
 * }} options
 * @returns {{ file: string, reason: string }[]}
 */
export function checkSite({ files, origin, vercel, isExecutable = () => false }) {
  const problems = [];
  const fail = (file, reason) => problems.push({ file, reason });
  const site = new URL(origin);

  const text = (file) => {
    try {
      return decoder.decode(files.get(file));
    } catch {
      fail(file, 'isn’t valid UTF-8');
      return '';
    }
  };

  for (const file of [...requiredFiles, ...Object.keys(requiredImages)]) {
    if (!files.has(file)) fail(file, 'is missing');
  }

  const csp = vercel instanceof Error ? undefined : cspDirectives(vercel);
  const allows = (directive, source) =>
    (csp?.[directive] ?? csp?.['default-src'] ?? []).includes(source);

  // Pages first: their ids (for #fragments), whether they're indexable, their headings.
  const pages = new Map();
  for (const file of [...files.keys()].filter((name) => name.endsWith('.html')).sort()) {
    const html = text(file);
    const tags = scanHtml(html);
    const ids = new Map();
    for (const tag of tags) {
      const id = tag.attributes.id ?? (tag.name === 'a' ? tag.attributes.name : undefined);
      if (id === undefined) continue;
      if (ids.has(id) && tag.attributes.id !== undefined) fail(file, `has two elements with id="${id}"`);
      ids.set(id, tag);
    }
    const robots = tags.find((tag) => tag.name === 'meta' && tag.attributes.name?.toLowerCase() === 'robots');
    const indexable = !/noindex/i.test(robots?.attributes.content ?? '');
    const headings = tags.filter((tag) => tag.name === 'h2' || tag.name === 'h3').map((tag) => textOf(html, tag));
    pages.set(file, { html, tags, ids, indexable, headings });
  }

  /** Checks one address found in `file`; `loads` is true when the browser fetches it as a resource. */
  const checkUrl = (file, raw, { what, loads, base }) => {
    const value = raw.trim();
    if (value === '') return fail(file, `${what} is empty`);
    if (/^javascript:/i.test(value)) return fail(file, `${what} is a javascript: URL, which the CSP blocks`);
    if (/^(mailto|tel|sms):/i.test(value)) return;
    if (/^data:/i.test(value)) {
      if (loads && !allows('img-src', 'data:')) fail(file, `${what} is a data: URL, which the CSP's img-src doesn't allow`);
      return;
    }
    let url;
    try {
      url = new URL(value, base);
    } catch {
      return fail(file, `${what} "${value}" isn't a valid address`);
    }
    if (url.origin !== site.origin) {
      if (loads) fail(file, `loads ${what} ${url.href} from another origin; the site loads nothing from third parties`);
      return;
    }
    if (url.pathname.endsWith('.html')) {
      return fail(file, `${what} ${value} names the .html file; link to ${pathForFile(url.pathname.slice(1))} (clean URLs)`);
    }
    if (url.pathname.length > 1 && url.pathname.endsWith('/')) {
      return fail(file, `${what} ${value} ends in "/", which redirects (trailingSlash: false)`);
    }
    const target = fileForPath(url.pathname, files);
    if (!target) return fail(file, `${what} ${value} doesn't resolve to a file in dist/`);
    if (url.hash.length > 1) {
      const id = decodeURIComponent(url.hash.slice(1));
      const page = pages.get(target);
      if (!page) return fail(file, `${what} ${value} has a #fragment, but ${target} isn't a page`);
      if (!page.ids.has(id)) fail(file, `${what} ${value}: ${target} has no element with id="${id}"`);
    } else if (url.hash === '#' || value === '#') {
      fail(file, `${what} is a bare "#"`);
    }
  };

  const seenTitles = new Map();
  const seenDescriptions = new Map();
  const indexablePages = new Map(); // canonical URL → file
  const twins = new Map(); // twin file → page file

  for (const [file, page] of pages) {
    const { tags, ids, indexable } = page;
    const base = new URL(pathForFile(file), site);
    const named = (name) => tags.filter((tag) => tag.name === name);
    const meta = (key, value) =>
      tags.filter((tag) => tag.name === 'meta' && tag.attributes[key]?.toLowerCase() === value);

    // One h1, a title and a description.
    const h1s = named('h1').length;
    if (h1s !== 1) fail(file, `has ${h1s} <h1> elements; a page has exactly one`);

    const titles = named('title');
    const title = decodeEntities(titles[0]?.content ?? '').replace(/\s+/g, ' ').trim();
    if (titles.length !== 1) fail(file, `has ${titles.length} <title> elements`);
    if (!title) fail(file, 'has an empty <title>');
    else if (title.length > limits.title) fail(file, `<title> is ${title.length} characters; keep it to ${limits.title}`);
    if (title && seenTitles.has(title)) fail(file, `has the same <title> as ${seenTitles.get(title)}: “${title}”`);
    seenTitles.set(title, file);

    const descriptions = meta('name', 'description');
    const description = (descriptions[0]?.attributes.content ?? '').trim();
    if (descriptions.length !== 1) fail(file, `has ${descriptions.length} meta descriptions`);
    if (!description) fail(file, 'has an empty meta description');
    else if (description.length > limits.description) {
      fail(file, `meta description is ${description.length} characters; keep it to ${limits.description}`);
    }
    if (description && seenDescriptions.has(description)) {
      fail(file, `has the same meta description as ${seenDescriptions.get(description)}`);
    }
    seenDescriptions.set(description, file);

    if (file === '404.html' && indexable) fail(file, 'should be noindex (<meta name="robots" content="noindex">)');

    // Canonical, twin and structured data, for pages search engines list.
    const canonicals = tags.filter((tag) => tag.name === 'link' && /(^|\s)canonical(\s|$)/i.test(tag.attributes.rel ?? ''));
    if (indexable) {
      if (canonicals.length !== 1) fail(file, `has ${canonicals.length} canonical links; an indexable page has one`);
      const href = canonicals[0]?.attributes.href;
      if (href) {
        let canonical;
        try {
          canonical = new URL(href);
        } catch {
          fail(file, `canonical "${href}" isn't an absolute address`);
        }
        if (canonical) {
          if (canonical.origin !== site.origin) fail(file, `canonical ${href} isn't on ${site.origin}`);
          else if (canonical.pathname !== pathForFile(file) || canonical.search || canonical.hash) {
            fail(file, `canonical ${href} isn't this page's address, ${new URL(pathForFile(file), site).href}`);
          } else indexablePages.set(canonical.href, file);
        }
      }

      const alternates = tags.filter(
        (tag) =>
          tag.name === 'link' &&
          /(^|\s)alternate(\s|$)/i.test(tag.attributes.rel ?? '') &&
          tag.attributes.type === 'text/markdown',
      );
      if (alternates.length !== 1) fail(file, 'has no <link rel="alternate" type="text/markdown"> to its Markdown twin');
      for (const alternate of alternates) {
        const twin = fileForPath(new URL(alternate.attributes.href ?? '', base).pathname, files);
        if (twin) twins.set(twin, file);
      }
    }

    const jsonLd = named('script').filter((tag) => tag.attributes.type?.toLowerCase() === 'application/ld+json');
    if (indexable && jsonLd.length === 0) fail(file, 'has no structured data (application/ld+json)');
    for (const block of jsonLd) {
      let data;
      try {
        data = JSON.parse(block.content ?? '');
      } catch (error) {
        fail(file, `has JSON-LD that doesn't parse: ${error.message}`);
        continue;
      }
      for (const item of Array.isArray(data) ? data : [data]) {
        if (!item || typeof item !== 'object' || !item['@context']) fail(file, 'has a JSON-LD block without @context');
      }
      // Addresses on this site in the data must exist (identifiers, @id, needn't).
      const visit = (value, key) => {
        if (typeof value === 'string') {
          if (key !== '@id' && value.startsWith(`${site.origin}/`)) checkUrl(file, value, { what: `JSON-LD ${key}`, loads: false, base });
        } else if (Array.isArray(value)) value.forEach((item) => visit(item, key));
        else if (value && typeof value === 'object') Object.entries(value).forEach(([name, item]) => visit(item, name));
      };
      visit(data, '');
    }

    // What the CSP would block.
    for (const tag of tags) {
      for (const name of Object.keys(tag.attributes)) {
        if (name === 'style') fail(file, `<${tag.name}> has a style attribute, which the CSP (style-src 'self') blocks`);
        else if (/^on[a-z]+$/.test(name)) fail(file, `<${tag.name}> has an inline ${name} handler, which the CSP blocks`);
      }
      if (tag.name === 'style') fail(file, 'has an inline <style> element, which the CSP (style-src \'self\') blocks');
      if (tag.name === 'script' && !tag.attributes.src && isExecutableScript(tag.attributes)) {
        fail(file, `has an inline <script${tag.attributes.type ? ` type="${tag.attributes.type}"` : ''}>, which the CSP (script-src 'self') blocks`);
      }
    }

    // Links and resources.
    for (const tag of tags) {
      const { name, attributes } = tag;
      const check = (value, loads, attribute) => checkUrl(file, value, { what: `<${name} ${attribute}>`, loads, base });
      switch (name) {
        case 'a':
        case 'area':
          if (attributes.href !== undefined) check(attributes.href, false, 'href');
          break;
        case 'link': {
          if (attributes.href === undefined) break;
          const rel = (attributes.rel ?? '').toLowerCase().split(/\s+/);
          const loads = rel.some((value) =>
            ['stylesheet', 'preload', 'modulepreload', 'icon', 'apple-touch-icon', 'manifest', 'prefetch'].includes(value),
          );
          check(attributes.href, loads, `rel="${attributes.rel ?? ''}" href`);
          break;
        }
        case 'script':
        case 'iframe':
        case 'embed':
        case 'audio':
        case 'video':
        case 'track':
          if (attributes.src !== undefined) check(attributes.src, true, 'src');
          if (attributes.poster !== undefined) check(attributes.poster, true, 'poster');
          break;
        case 'img':
        case 'source':
        case 'input':
          if (attributes.src !== undefined) check(attributes.src, true, 'src');
          if (attributes.srcset !== undefined) for (const url of srcsetUrls(attributes.srcset)) check(url, true, 'srcset');
          break;
        case 'object':
          if (attributes.data !== undefined) check(attributes.data, true, 'data');
          break;
        case 'use':
        case 'image':
          // SVG: <use href="#body"> must find its target in this page.
          for (const attribute of ['href', 'xlink:href']) {
            const value = attributes[attribute];
            if (value === undefined) continue;
            if (value.startsWith('#')) {
              if (!ids.has(value.slice(1))) fail(file, `<${name} ${attribute}="${value}"> has no target on the page`);
            } else check(value, true, attribute);
          }
          break;
        case 'meta': {
          const property = (attributes.property ?? attributes.name ?? '').toLowerCase();
          if (['og:image', 'og:image:url', 'twitter:image', 'og:url'].includes(property) && attributes.content) {
            if (!/^https?:\/\//.test(attributes.content)) fail(file, `${property} must be an absolute address`);
            else check(attributes.content, false, `content (${property})`);
          }
          break;
        }
      }
    }
  }

  // Stylesheets: nothing from elsewhere, and every url() there.
  for (const file of [...files.keys()].filter((name) => name.endsWith('.css'))) {
    const css = text(file).replace(/\/\*[\s\S]*?\*\//g, '');
    const base = new URL(`/${file}`, site);
    for (const match of css.matchAll(/url\(\s*(?:"([^"]*)"|'([^']*)'|([^)\s]*))\s*\)|@import\s+(?:"([^"]*)"|'([^']*)')/g)) {
      const value = match[1] ?? match[2] ?? match[3] ?? match[4] ?? match[5] ?? '';
      if (value.startsWith('#')) continue; // an SVG reference, e.g. url(#mask)
      checkUrl(file, value, { what: 'url()', loads: true, base });
    }
  }

  // The sitemap lists exactly the indexable pages.
  if (files.has('sitemap.xml')) {
    const xml = text('sitemap.xml');
    const locations = [...xml.matchAll(/<loc>\s*([^<]*?)\s*<\/loc>/g)].map((match) => decodeEntities(match[1]));
    if (!xml.includes('http://www.sitemaps.org/schemas/sitemap/0.9')) fail('sitemap.xml', 'has no sitemaps.org namespace');
    for (const location of locations) {
      if (!indexablePages.has(location)) {
        fail('sitemap.xml', `lists ${location}, which isn't an indexable page's canonical address`);
      }
    }
    for (const [url, file] of indexablePages) {
      if (!locations.includes(url)) fail('sitemap.xml', `doesn't list ${url} (${file})`);
    }
  }

  // robots.txt lets crawlers in and names the sitemap.
  if (files.has('robots.txt')) {
    const robots = text('robots.txt');
    if (!robots.split('\n').some((line) => line.trim() === `Sitemap: ${new URL('/sitemap.xml', site).href}`)) {
      fail('robots.txt', `doesn't point to ${new URL('/sitemap.xml', site).href}`);
    }
    if (robots.split('\n').some((line) => /^\s*disallow:\s*\/\s*$/i.test(line))) {
      fail('robots.txt', 'disallows the whole site');
    }
  }

  // Markdown for assistants: the twins and the llms files.
  const markdownFiles = new Set(['llms.txt', 'llms-full.txt', ...twins.keys()]);
  if (files.has('index.html') && pages.get('index.html')?.indexable && !twins.has('index.html.md')) {
    fail('index.html.md', 'is missing, or the home page doesn’t link to it');
  }
  for (const file of markdownFiles) {
    if (!files.has(file)) continue;
    const markdown = text(file);
    if (!markdown.startsWith('# ')) fail(file, 'doesn’t start with a "# " heading');
    if (markdown.includes(' ')) fail(file, 'has no-break spaces; Markdown wants plain ones');
    if (/<(script|style|div|span|kbd)\b/i.test(markdown)) fail(file, 'has HTML in it; write Markdown');
    for (const match of markdown.matchAll(/\]\((\S+?)\)/g)) {
      if (match[1].startsWith(`${site.origin}/`) || match[1] === site.origin) {
        checkUrl(file, match[1], { what: 'link', loads: false, base: site });
      } else if (!/^[a-z][a-z\d+.-]*:/i.test(match[1])) {
        fail(file, `links to "${match[1]}"; links in Markdown for assistants are absolute`);
      }
    }
    const page = pages.get(twins.get(file));
    if (page) {
      const headings = new Set(page.headings);
      for (const match of markdown.matchAll(/^#{2,3} (.+)$/gm)) {
        const heading = match[1].replace(/\\(.)/g, '$1').trim();
        if (!headings.has(heading)) fail(file, `has the heading “${heading}”, which ${twins.get(file)} doesn’t`);
      }
    }
  }
  if (files.has('llms.txt')) {
    const llms = text('llms.txt');
    if (!/^> \S/m.test(llms)) fail('llms.txt', 'has no "> " summary (llmstxt.org)');
    if (!/^## /m.test(llms)) fail('llms.txt', 'has no "## " sections of links (llmstxt.org)');
  }

  // Images and icons.
  for (const [file, [width, height]] of Object.entries(requiredImages)) {
    if (!files.has(file)) continue;
    const size = pngSize(files.get(file));
    if (!size) fail(file, 'isn’t a PNG');
    else if (size[0] !== width || size[1] !== height) fail(file, `is ${size[0]} × ${size[1]}; it should be ${width} × ${height}`);
  }
  if (files.has('favicon.ico')) {
    const sizes = icoSizes(files.get('favicon.ico'));
    if (!sizes) fail('favicon.ico', 'isn’t an ICO file');
    else if (!sizes.includes(32)) fail('favicon.ico', `has no 32 px image (it has ${sizes.join(', ')})`);
  }

  // The web manifest.
  if (files.has('manifest.webmanifest')) {
    let manifest;
    try {
      manifest = JSON.parse(text('manifest.webmanifest'));
    } catch (error) {
      fail('manifest.webmanifest', `doesn't parse: ${error.message}`);
    }
    if (manifest) {
      for (const key of ['name', 'short_name', 'start_url', 'display', 'theme_color', 'background_color']) {
        if (!manifest[key]) fail('manifest.webmanifest', `has no ${key}`);
      }
      if (manifest.start_url) checkUrl('manifest.webmanifest', manifest.start_url, { what: 'start_url', loads: false, base: site });
      const icons = Array.isArray(manifest.icons) ? manifest.icons : [];
      if (icons.length === 0) fail('manifest.webmanifest', 'has no icons');
      if (!icons.some((icon) => /(^|\s)maskable(\s|$)/.test(icon.purpose ?? ''))) {
        fail('manifest.webmanifest', 'has no maskable icon');
      }
      for (const icon of icons) {
        checkUrl('manifest.webmanifest', icon.src ?? '', { what: 'icon', loads: true, base: site });
        const target = fileForPath(new URL(icon.src ?? '', site).pathname, files);
        const size = target && pngSize(files.get(target));
        if (size && icon.sizes !== `${size[0]}x${size[1]}`) {
          fail('manifest.webmanifest', `says ${icon.src} is ${icon.sizes}; it's ${size[0]}x${size[1]}`);
        }
      }
    }
  }

  // vercel.json: it parses, sets the CSP, and its ignoreCommand script is there.
  if (vercel instanceof Error) {
    fail('vercel.json', `doesn't parse: ${vercel.message}`);
  } else if (!vercel) {
    fail('vercel.json', 'is missing');
  } else {
    if (!csp) fail('vercel.json', 'sets no Content-Security-Policy header');
    for (const directive of ['script-src', 'style-src']) {
      if ((csp?.[directive] ?? []).some((source) => /unsafe-inline|unsafe-eval/.test(source))) {
        fail('vercel.json', `${directive} allows unsafe inline code; the site needs none`);
      }
    }
    const command = vercel.ignoreCommand;
    if (typeof command !== 'string' || command.trim() === '') {
      fail('vercel.json', 'has no ignoreCommand');
    } else {
      const script = /(?:^|\s)((?:\.\/)?[\w./-]+\.sh)\b/.exec(command)?.[1];
      if (!script) fail('vercel.json', `ignoreCommand "${command}" doesn't run a .sh script`);
      else if (!isExecutable(script.replace(/^\.\//, ''))) {
        fail('vercel.json', `ignoreCommand runs ${script}, which is missing or not executable (chmod +x)`);
      }
    }
  }

  return problems;
}

// MARK: Command line

/** Every file under a directory, by its path relative to it (with "/"). */
function readTree(directory) {
  const files = new Map();
  const walk = (folder) => {
    for (const entry of readdirSync(folder, { withFileTypes: true })) {
      const path = join(folder, entry.name);
      if (entry.isDirectory()) walk(path);
      else if (entry.isFile()) files.set(relative(directory, path).split(sep).join('/'), readFileSync(path));
    }
  };
  walk(directory);
  return files;
}

async function main() {
  const started = performance.now();
  const siteDir = fileURLToPath(new URL('..', import.meta.url));
  const distDir = join(siteDir, 'dist');
  try {
    if (!statSync(distDir).isDirectory()) throw new Error();
  } catch {
    console.error('check:dist: no dist/ directory; run `npm run build` first.');
    process.exit(1);
  }
  // The same address astro.config.mjs builds with.
  const { productionUrl } = await import('../src/config.ts');
  const origin = process.env.SITE_URL ?? productionUrl;

  let vercel;
  try {
    vercel = JSON.parse(readFileSync(join(siteDir, 'vercel.json'), 'utf8'));
  } catch (error) {
    vercel = error.code === 'ENOENT' ? undefined : error;
  }
  const isExecutable = (path) => {
    try {
      const stat = statSync(join(siteDir, path));
      return stat.isFile() && (stat.mode & 0o111) !== 0;
    } catch {
      return false;
    }
  };

  const files = readTree(distDir);
  const problems = checkSite({ files, origin, vercel, isExecutable });
  const pages = [...files.keys()].filter((file) => file.endsWith('.html')).length;
  const elapsed = Math.round(performance.now() - started);
  if (problems.length > 0) {
    for (const { file, reason } of problems) console.error(`✗ ${file}: ${reason}`);
    console.error(`\ncheck:dist: ${problems.length} problem${problems.length === 1 ? '' : 's'} in dist/ (${pages} pages, ${files.size} files, ${origin}).`);
    process.exit(1);
  }
  console.log(`check:dist: dist/ is fine: ${pages} pages, ${files.size} files, checked for ${origin} in ${elapsed} ms.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
