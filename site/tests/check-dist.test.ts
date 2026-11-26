// scripts/check-dist.mjs: the readers it's built on, and checkSite on a
// small made-up site, once whole and then broken one way at a time.
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import {
  checkSite,
  fileForPath,
  icoSizes,
  ignoreScriptUrls,
  isExecutableScript,
  parseAttributes,
  pathForFile,
  pngSize,
  scanHtml,
  softwareVersionText,
  srcsetUrls,
  textOf,
} from '../scripts/check-dist.mjs';

const origin = 'https://example.test';
const encode = (text: string): Uint8Array => new TextEncoder().encode(text);

function png(width: number, height: number): Uint8Array {
  const bytes = new Uint8Array(33);
  bytes.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
  const view = new DataView(bytes.buffer);
  view.setUint32(16, width);
  view.setUint32(20, height);
  return bytes;
}

function ico(...sizes: number[]): Uint8Array {
  const bytes = new Uint8Array(6 + 16 * sizes.length);
  const view = new DataView(bytes.buffer);
  view.setUint16(2, 1, true);
  view.setUint16(4, sizes.length, true);
  sizes.forEach((size, index) => (bytes[6 + 16 * index] = size));
  return bytes;
}

interface PageOptions {
  title: string;
  description: string;
  path: string;
  twin?: string;
  head?: string;
  body?: string;
  /** The page's JSON-LD, when it has a twin. */
  data?: string;
}

function page({ title, description, path, twin, head = '', body = '', data = '{"@context":"https://schema.org","@type":"WebPage"}' }: PageOptions): string {
  const indexed = twin
    ? `<link rel="canonical" href="${origin}${path}"><link rel="alternate" type="text/markdown" href="${origin}${twin}">` +
      `<script type="application/ld+json">${data}</script>`
    : '<meta name="robots" content="noindex">';
  return (
    `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>${title}</title>` +
    `<meta name="description" content="${description}">${indexed}` +
    '<link rel="stylesheet" href="/_astro/site.css"><link rel="icon" href="/favicon.svg">' +
    `<script type="module" src="/_astro/site.js"></script>${head}</head>` +
    `<body><a href="#content">Skip</a><main id="content"><h1>${title}</h1>${body}</main></body></html>`
  );
}

/** A small site that passes every check. Each test breaks one thing. */
function site(): Map<string, Uint8Array> {
  const files = new Map<string, string | Uint8Array>([
    [
      'index.html',
      page({
        title: 'Home',
        description: 'The home page.',
        path: '/',
        twin: '/index.html.md',
        data: '{"@context":"https://schema.org","@graph":[{"@type":"SoftwareApplication","name":"Site","softwareVersion":"1.2.0"}]}',
        body: '<h2 id="more">More</h2><a href="/about">About</a> <a href="/about#team">Team</a> <a href="https://elsewhere.test/">Out</a>',
      }),
    ],
    [
      'about.html',
      page({ title: 'About', description: 'About us.', path: '/about', twin: '/about.md', body: '<h2 id="team">Team</h2>' }),
    ],
    ['404.html', page({ title: 'Not found', description: 'Nothing here.', path: '/404', body: '<a href="/">Home</a>' })],
    ['index.html.md', `# Home\n\n## More\n\n[About](${origin}/about)\n`],
    ['about.md', '# About\n\n## Team\n'],
    ['llms.txt', `# Site\n\n> A site.\n\n## Pages\n\n- [Home](${origin}/index.html.md): the home page\n`],
    ['llms-full.txt', '# Site\n\nEverything.\n'],
    ['robots.txt', `User-agent: *\nAllow: /\n\nSitemap: ${origin}/sitemap.xml\n`],
    [
      'sitemap.xml',
      '<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' +
        `<url><loc>${origin}/</loc></url><url><loc>${origin}/about</loc></url></urlset>`,
    ],
    [
      'manifest.webmanifest',
      JSON.stringify({
        name: 'Site',
        short_name: 'Site',
        start_url: '/',
        display: 'browser',
        theme_color: '#fff',
        background_color: '#fff',
        icons: [
          { src: '/icon-512.png', sizes: '512x512', type: 'image/png' },
          { src: '/icon-maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      }),
    ],
    ['_astro/site.css', 'body { background: url(/favicon.svg) }'],
    ['_astro/site.js', 'console.log(1)'],
    ['favicon.svg', '<svg xmlns="http://www.w3.org/2000/svg"/>'],
    ['favicon.ico', ico(16, 32)],
    ['og.png', png(1200, 630)],
    ['apple-touch-icon.png', png(180, 180)],
    ['icon-192.png', png(192, 192)],
    ['icon-512.png', png(512, 512)],
    ['icon-maskable-512.png', png(512, 512)],
  ]);
  return new Map([...files].map(([name, data]) => [name, typeof data === 'string' ? encode(data) : data]));
}

const vercel = {
  ignoreCommand: 'sh scripts/vercel-ignore.sh || exit 1',
  headers: [
    {
      source: '/(.*)',
      headers: [{ key: 'Content-Security-Policy', value: "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'" }],
    },
  ],
};

const repoUrl = 'https://github.com/example/site';
const config = { productionUrl: origin, repoUrl };

/** The top of scripts/vercel-ignore.sh, its addresses mirroring the config. */
const ignoreScript = `#!/bin/sh\n# The production site and the repository.\nsite_url='${origin}'\nrepo_url='${repoUrl}'\n`;

interface Options {
  vercel?: unknown;
  isExecutable?: (path: string) => boolean;
  readFile?: (path: string) => string | undefined;
}

function problems(files: Map<string, Uint8Array>, options: Options = {}): string[] {
  const readFile = (path: string) => (path === 'scripts/vercel-ignore.sh' ? ignoreScript : undefined);
  return checkSite({ files, origin, vercel, isExecutable: () => true, readFile, config, ...options }).map(
    ({ file, reason }) => `${file}: ${reason}`,
  );
}

/** The site with one file's text changed. */
function edit(file: string, change: (text: string) => string): Map<string, Uint8Array> {
  const files = site();
  files.set(file, encode(change(new TextDecoder().decode(files.get(file)))));
  return files;
}

function assertProblem(found: string[], pattern: RegExp): void {
  assert.ok(
    found.some((problem) => pattern.test(problem)),
    `expected a problem matching ${pattern}, got:\n  ${found.join('\n  ') || '(none)'}`,
  );
}

describe('reading HTML', () => {
  test('finds start tags and their attributes', () => {
    const tags = scanHtml('<a href="/x" class=link data-on>One</a><img src=\'/y.png\' alt="a > b">');
    assert.deepEqual(
      tags.map((tag) => [tag.name, tag.attributes]),
      [
        ['a', { href: '/x', class: 'link', 'data-on': '' }],
        ['img', { src: '/y.png', alt: 'a > b' }],
      ],
    );
  });

  test('skips comments and what scripts and styles contain', () => {
    const html = '<!-- <a href="/c"> --><script>if (a<b) document.write("<a href=/s>")</script><style>a{}</style><p>';
    const tags = scanHtml(html);
    assert.deepEqual(
      tags.map((tag) => tag.name),
      ['script', 'style', 'p'],
    );
    assert.equal(tags[0]?.content, 'if (a<b) document.write("<a href=/s>")');
  });

  test('decodes entities in attributes and text', () => {
    assert.deepEqual(parseAttributes('title="Kept &amp; co" alt=\'&#8984;&#x2318;\''), { title: 'Kept & co', alt: '⌘⌘' });
    const html = '<h2 id="x">Report a <em>security</em> &amp; privacy issue</h2>';
    assert.equal(textOf(html, scanHtml(html)[0]), 'Report a security & privacy issue');
  });

  test('reads the version as the ignore script does', () => {
    assert.equal(softwareVersionText('<script type="application/ld+json">{"name":"Kept","softwareVersion":"0.1.0"}</script>'), '0.1.0');
    assert.equal(softwareVersionText('{"softwareVersion": "1.0.0-beta.2"}'), '1.0.0-beta.2');
    assert.equal(softwareVersionText('{"softwareVersion":\n"0.1.0"}'), undefined, 'split over two lines');
    assert.equal(softwareVersionText('{"softwareVersion":"0.1 beta"}'), undefined);
  });

  test('reads the ignore script’s addresses', () => {
    assert.deepEqual(ignoreScriptUrls(ignoreScript), { site: origin, repo: repoUrl });
    assert.deepEqual(ignoreScriptUrls('site_url="https://a.test"\nrepo_url=https://github.com/a/b\n'), {
      site: 'https://a.test',
      repo: 'https://github.com/a/b',
    });
    assert.deepEqual(ignoreScriptUrls('echo hi\n'), { site: undefined, repo: undefined });
  });

  test('reads srcsets', () => {
    assert.deepEqual(srcsetUrls('/a.png 760w, /b.png 1140w,/c.png 2x'), ['/a.png', '/b.png', '/c.png']);
  });

  test('tells code from data in <script>', () => {
    assert.equal(isExecutableScript({}), true);
    assert.equal(isExecutableScript({ type: 'module' }), true);
    assert.equal(isExecutableScript({ type: 'text/javascript' }), true);
    assert.equal(isExecutableScript({ type: 'importmap' }), true);
    assert.equal(isExecutableScript({ type: 'application/ld+json' }), false);
    assert.equal(isExecutableScript({ type: 'application/json' }), false);
  });
});

describe('addresses', () => {
  const files = site();

  test('resolve as the host serves them, with clean URLs', () => {
    assert.equal(fileForPath('/', files), 'index.html');
    assert.equal(fileForPath('/about', files), 'about.html');
    assert.equal(fileForPath('/index.html.md', files), 'index.html.md');
    assert.equal(fileForPath('/_astro/site.css', files), '_astro/site.css');
    assert.equal(fileForPath('/missing', files), undefined);
  });

  test('of pages', () => {
    assert.equal(pathForFile('index.html'), '/');
    assert.equal(pathForFile('about.html'), '/about');
    assert.equal(pathForFile('docs/index.html'), '/docs');
  });
});

describe('binary formats', () => {
  test('a PNG’s size', () => {
    assert.deepEqual(pngSize(png(1200, 630)), [1200, 630]);
    assert.equal(pngSize(encode('not a png at all, really not')), undefined);
  });

  test('an ICO’s sizes', () => {
    assert.deepEqual(icoSizes(ico(16, 32)), [16, 32]);
    assert.equal(icoSizes(png(32, 32)), undefined);
  });
});

describe('checkSite', () => {
  test('passes a whole site', () => {
    assert.deepEqual(problems(site()), []);
  });

  test('links and fragments must resolve', () => {
    assertProblem(problems(edit('about.html', (html) => html.replace('</main>', '<a href="/gone">x</a></main>'))), /^about\.html: .*\/gone doesn't resolve/);
    assertProblem(problems(edit('index.html', (html) => html.replace('/about#team', '/about#nobody'))), /^index\.html: .*about\.html has no element with id="nobody"/);
    assertProblem(problems(edit('index.html', (html) => html.replace('href="#content"', 'href="#nowhere"'))), /id="nowhere"/);
    assertProblem(problems(edit('index.html', (html) => html.replace('href="/about"', 'href="/about.html"'))), /names the \.html file; link to \/about/);
    assertProblem(problems(edit('index.html', (html) => html.replace('href="/about"', 'href="/about/"'))), /ends in "\/", which redirects/);
  });

  test('a page has one h1, a title and a description within limits, all its own', () => {
    assertProblem(problems(edit('about.html', (html) => html.replace('</main>', '<h1>Again</h1></main>'))), /^about\.html: has 2 <h1>/);
    assertProblem(problems(edit('about.html', (html) => html.replace('<title>About', `<title>${'A'.repeat(61)}`))), /^about\.html: <title> is 61 characters; keep it to 60/);
    assertProblem(problems(edit('about.html', (html) => html.replace('<title>About', '<title>Home'))), /same <title> as/);
    assertProblem(problems(edit('about.html', (html) => html.replace('content="About us."', 'content=""'))), /empty meta description/);
    assertProblem(problems(edit('about.html', (html) => html.replace('content="About us."', `content="${'x'.repeat(156)}"`))), /meta description is 156 characters/);
  });

  test('indexable pages have a canonical on the origin that names them', () => {
    assertProblem(problems(edit('about.html', (html) => html.replace(`${origin}/about"`, 'https://other.test/about"'))), /canonical .* isn't on https:\/\/example\.test/);
    assertProblem(problems(edit('about.html', (html) => html.replace(`href="${origin}/about"`, `href="${origin}/"`))), /isn't this page's address/);
    assertProblem(problems(edit('404.html', (html) => html.replace('<meta name="robots" content="noindex">', ''))), /^404\.html: should be noindex/);
  });

  test('the sitemap lists exactly the indexable pages', () => {
    assertProblem(problems(edit('sitemap.xml', (xml) => xml.replace(`<url><loc>${origin}/about</loc></url>`, ''))), /^sitemap\.xml: doesn't list https:\/\/example\.test\/about/);
    assertProblem(problems(edit('sitemap.xml', (xml) => xml.replace('</urlset>', `<url><loc>${origin}/404</loc></url></urlset>`))), /lists https:\/\/example\.test\/404/);
  });

  test('the home page states the app’s version where the ignore script reads it', () => {
    assertProblem(problems(edit('index.html', (html) => html.replace(',"softwareVersion":"1.2.0"', ''))), /^index\.html: states no softwareVersion in its JSON-LD/);
    assertProblem(problems(edit('index.html', (html) => html.replace('"softwareVersion":"1.2.0"', '"softwareVersion":\n"1.2.0"'))), /^index\.html: JSON-LD softwareVersion "1\.2\.0" isn't written the way scripts\/vercel-ignore\.sh reads it/);
    assert.deepEqual(problems(edit('about.html', (html) => html.replace('WebPage', 'AboutPage'))), [], 'other pages needn’t');
  });

  test('structured data parses and has a @context', () => {
    assertProblem(problems(edit('about.html', (html) => html.replace('"@type":"WebPage"}', '"@type":"WebPage"'))), /JSON-LD that doesn't parse/);
    assertProblem(problems(edit('about.html', (html) => html.replace('"@context":"https://schema.org",', ''))), /JSON-LD block without @context/);
    assertProblem(problems(edit('about.html', (html) => html.replace('"@type":"WebPage"', `"@type":"WebPage","image":"${origin}/nope.png"`))), /JSON-LD image .*nope\.png doesn't resolve/);
  });

  test('nothing the CSP would block', () => {
    assertProblem(problems(edit('about.html', (html) => html.replace('</head>', '<style>p{}</style></head>'))), /inline <style> element/);
    assertProblem(problems(edit('about.html', (html) => html.replace('<main', '<main style="color: red"'))), /<main> has a style attribute/);
    assertProblem(problems(edit('about.html', (html) => html.replace('<main', '<main onclick="go()"'))), /inline onclick handler/);
    assertProblem(problems(edit('about.html', (html) => html.replace('</head>', '<script>go()</script></head>'))), /inline <script>/);
    assertProblem(problems(edit('about.html', (html) => html.replace('</head>', '<script type="module">go()</script></head>'))), /inline <script type="module">/);
    assertProblem(problems(edit('about.html', (html) => html.replace('</main>', '<a href="javascript:go()">x</a></main>'))), /javascript: URL/);
    assertProblem(problems(edit('about.html', (html) => html.replace('</main>', '<img src="data:image/png;base64,AAAA" alt=""></main>'))), /data: URL/);
  });

  test('nothing loads from another origin', () => {
    assertProblem(problems(edit('about.html', (html) => html.replace('/_astro/site.js', 'https://cdn.test/x.js'))), /loads <script src> https:\/\/cdn\.test\/x\.js from another origin/);
    assertProblem(problems(edit('about.html', (html) => html.replace('/_astro/site.css', '//cdn.test/x.css'))), /loads <link rel="stylesheet" href> https:\/\/cdn\.test\/x\.css/);
    assertProblem(problems(edit('about.html', (html) => html.replace('</main>', '<img src="https://img.test/a.png" alt=""></main>'))), /loads <img src>/);
    assertProblem(problems(edit('_astro/site.css', (css) => `@font-face { src: url("https://fonts.test/a.woff2") }\n${css}`)), /^_astro\/site\.css: loads url\(\) https:\/\/fonts\.test/);
    assertProblem(problems(edit('_astro/site.css', (css) => `${css}\n@import "https://fonts.test/a.css";`)), /^_astro\/site\.css: loads url\(\)/);
  });

  test('the files for crawlers and assistants are there and well formed', () => {
    for (const file of ['robots.txt', 'llms.txt', 'llms-full.txt', 'manifest.webmanifest', 'favicon.ico', 'og.png']) {
      const files = site();
      files.delete(file);
      assertProblem(problems(files), new RegExp(`^${file.replace('.', '\\.')}: is missing`));
    }
    const files = site();
    files.set('og.png', png(1200, 600));
    assertProblem(problems(files), /^og\.png: is 1200 × 600; it should be 1200 × 630/);
    assertProblem(problems(edit('robots.txt', () => 'User-agent: *\nDisallow: /\n')), /^robots\.txt: doesn't point to .*sitemap\.xml/);
    assertProblem(problems(edit('llms.txt', (text) => text.replace('> A site.', 'A site.'))), /^llms\.txt: has no "> " summary/);
    assertProblem(problems(edit('index.html.md', (text) => text.replace('## More', '## Less'))), /^index\.html\.md: has the heading “Less”, which index\.html doesn’t/);
    assertProblem(problems(edit('index.html.md', (text) => text.replace(`${origin}/about`, '/about'))), /links to "\/about"; links in Markdown for assistants are absolute/);
    assertProblem(problems(edit('manifest.webmanifest', (text) => text.replace(',"purpose":"maskable"', ''))), /has no maskable icon/);
  });

  test('vercel.json parses and its ignoreCommand script is executable', () => {
    assertProblem(problems(site(), { vercel: new SyntaxError('Unexpected token') }), /^vercel\.json: doesn't parse/);
    assertProblem(problems(site(), { isExecutable: () => false }), /runs scripts\/vercel-ignore\.sh, which is missing or not executable/);
    const loose = structuredClone(vercel);
    loose.headers[0]!.headers[0]!.value += "; style-src 'self' 'unsafe-inline'";
    assertProblem(problems(site(), { vercel: loose }), /allows unsafe inline code/);
  });

  test('the ignore script asks the site’s own addresses', () => {
    const script = (text: string) => ({ readFile: () => text });
    assertProblem(
      problems(site(), script(ignoreScript.replace(origin, 'https://old.example.test'))),
      /^scripts\/vercel-ignore\.sh: site_url is "https:\/\/old\.example\.test"; it must be "https:\/\/example\.test", src\/config\.ts's productionUrl/,
    );
    assertProblem(
      problems(site(), script(ignoreScript.replace(repoUrl, 'https://github.com/example/old'))),
      /^scripts\/vercel-ignore\.sh: repo_url is "https:\/\/github\.com\/example\/old"; it must be "https:\/\/github\.com\/example\/site", src\/config\.ts's repoUrl/,
    );
    assertProblem(problems(site(), script('#!/bin/sh\n')), /^scripts\/vercel-ignore\.sh: site_url is missing/);
    assertProblem(problems(site(), { readFile: () => undefined }), /^scripts\/vercel-ignore\.sh: repo_url is missing/);
  });
});
