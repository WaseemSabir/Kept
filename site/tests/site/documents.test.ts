// What the site tells search engines and assistants: page titles and
// descriptions, the Markdown twins, llms.txt and llms-full.txt, robots.txt
// and the sitemap.
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { questions } from '../../src/data/faq.ts';
import { home, indexedPages, notFoundPage, privacyPage, shortcutsPage } from '../../src/data/pages.ts';
import type { Release } from '../../src/data/release.ts';
import { globalShortcuts, panelShortcuts } from '../../src/data/shortcuts.ts';
import { aiAgents, robotsTxt, sitemapXml } from '../../src/lib/crawlers.ts';
import {
  homeMarkdown,
  llmsFullTxt,
  llmsTxt,
  privacyMarkdown,
  shortcutsMarkdown,
  type SiteContext,
} from '../../src/lib/documents.ts';
import { toMarkdown, toPlainText } from '../../src/lib/inline.ts';
import { table } from '../../src/lib/markdown.ts';

const origin = 'https://kept.example';
const release: Release = { version: '0.1.0', downloadUrl: 'https://github.com/WaseemSabir/Kept/releases/latest', source: 'info-plist' };
const context: SiteContext = { origin, release };
const screenshots = [{ url: `${origin}/_astro/a.webp`, alt: 'The panel.', caption: 'Searching.' }];

const documents = {
  'index.html.md': homeMarkdown(context, screenshots),
  'shortcuts.md': shortcutsMarkdown(context),
  'privacy.md': privacyMarkdown(context),
  'llms.txt': llmsTxt(context),
  'llms-full.txt': llmsFullTxt(context),
};

const links = (markdown: string): string[] => [...markdown.matchAll(/\]\((\S+?)\)/g)].map((match) => match[1] ?? '');

describe('pages', () => {
  test('titles and descriptions fit in search results', () => {
    for (const page of [...indexedPages, notFoundPage]) {
      assert.ok(page.title.length <= 60, `${page.id}: title is ${page.title.length} characters`);
      assert.ok(page.description.length <= 155, `${page.id}: description is ${page.description.length} characters`);
    }
    assert.equal(home.title, 'Kept: a keyboard-first clipboard manager for the Mac');
  });

  test('“clipboard manager”, the words people search for, is in the home description and the first answer', () => {
    assert.match(home.description, /clipboard manager/);
    assert.match(toPlainText(questions[0]?.answer[0] ?? ''), /clipboard manager/);
  });

  test('canonical paths have no trailing slash and twins follow llmstxt.org', () => {
    assert.deepEqual(
      indexedPages.map((page) => [page.path, page.markdownPath]),
      [
        ['/', '/index.html.md'],
        ['/shortcuts', '/shortcuts.md'],
        ['/privacy', '/privacy.md'],
      ],
    );
    assert.equal(notFoundPage.indexable, false);
  });
});

describe('inline copy as Markdown and plain text', () => {
  test('keys become code spans and no-break spaces plain ones', () => {
    assert.equal(toMarkdown('{↑} {↓} or {⌃P}'), '`↑` `↓` or `⌃P`');
    assert.equal(toPlainText('Press {⇧⌘V} now.'), 'Press ⇧⌘V now.');
  });

  test('site-relative links become absolute; others are left as written', () => {
    assert.equal(toMarkdown('[All](/shortcuts)', { base: origin }), `[All](${origin}/shortcuts)`);
    assert.equal(toMarkdown('[markers](http://nspasteboard.org)', { base: origin }), '[markers](http://nspasteboard.org)');
  });

  test('running text that looks like Markdown is escaped', () => {
    assert.equal(toMarkdown('a_b *c* [d] <e>'), 'a\\_b \\*c\\* \\[d\\] \\<e>');
  });

  test('table cells can’t split a row', () => {
    assert.equal(table(['A', 'B'], [['x | y', 'z']]), '| A | B |\n| --- | --- |\n| x \\| y | z |');
  });
});

describe('Markdown for assistants', () => {
  test('every document starts with a title and holds no HTML or no-break spaces', () => {
    for (const [name, markdown] of Object.entries(documents)) {
      assert.match(markdown, /^# \S/, name);
      assert.doesNotMatch(markdown, /<(kbd|code|strong|a|span|div)\b/, name);
      assert.ok(!markdown.includes(' '), `${name} has a no-break space`);
      assert.ok(!markdown.includes('\n\n\n'), `${name} has a double blank line`);
      assert.ok(markdown.endsWith('\n') && !markdown.endsWith('\n\n'), `${name} should end in one newline`);
    }
  });

  test('every link is absolute', () => {
    for (const [name, markdown] of Object.entries(documents)) {
      for (const link of links(markdown)) assert.match(link, /^https?:\/\//, `${name}: ${link}`);
    }
  });

  test('the home twin answers every question; llms-full.txt has every question and every shortcut', () => {
    for (const item of questions) {
      assert.ok(documents['index.html.md'].includes(`### ${item.question}`), item.question);
      assert.ok(documents['llms-full.txt'].includes(`### ${item.question}`), item.question);
    }
    const rows = documents['llms-full.txt'].split('\n').filter((line) => line.startsWith('| ') && !line.startsWith('| Keys') && !line.startsWith('| ---'));
    assert.equal(rows.length, globalShortcuts.length + panelShortcuts.length);
    assert.ok(documents['llms-full.txt'].includes('Version 0.1.0 for macOS 14 or later'));
    assert.ok(documents['llms-full.txt'].includes(release.downloadUrl));
    assert.match(documents['llms-full.txt'], /MIT license/);
  });

  test('the shortcuts twin is a table of every shortcut', () => {
    const rows = documents['shortcuts.md'].split('\n').filter((line) => line.startsWith('| ') && !line.startsWith('| Keys') && !line.startsWith('| ---'));
    assert.equal(rows.length, globalShortcuts.length + panelShortcuts.length);
    assert.ok(rows.includes('| `⇧⌘V` | Open or close Kept |'));
  });

  test('llms.txt: a name, a summary, facts, then sections of links with notes', () => {
    const lines = documents['llms.txt'].split('\n');
    assert.equal(lines[0], '# Kept');
    assert.equal(lines[2], `> ${home.description}`);
    for (const page of [home, shortcutsPage, privacyPage]) {
      assert.ok(documents['llms.txt'].includes(`](${origin}${page.markdownPath}): `), page.id);
    }
    assert.ok(documents['llms.txt'].includes(`](${origin}/llms-full.txt): `));
    for (const line of lines.filter((item) => item.startsWith('- '))) assert.match(line, /^- \[[^\]]+\]\(\S+\): \S/, line);
  });

  test('without a known version, nothing claims one', () => {
    const unknown: SiteContext = { origin, release: { downloadUrl: release.downloadUrl, source: 'info-plist' } };
    assert.doesNotMatch(llmsTxt(unknown), /current version/);
    assert.match(homeMarkdown(unknown, []), /The latest version for macOS 14 or later/);
    assert.doesNotMatch(homeMarkdown(unknown, []), /## Screenshots/);
  });
});

describe('robots.txt and the sitemap', () => {
  test('robots.txt lets everyone in, names the AI crawlers and points to the sitemap', () => {
    const robots = robotsTxt(origin);
    assert.match(robots, /^User-agent: \*\nAllow: \/$/m);
    for (const agent of aiAgents) assert.match(robots, new RegExp(`^User-agent: ${agent}$`, 'm'));
    assert.doesNotMatch(robots, /Disallow/);
    assert.match(robots, new RegExp(`^Sitemap: ${origin}/sitemap.xml$`, 'm'));
    assert.match(robots, /^[\x00-\x7f]*$/, 'robots.txt is ASCII');
  });

  test('the sitemap lists the indexable pages and nothing else', () => {
    const xml = sitemapXml(origin, [...indexedPages, notFoundPage]);
    const locations = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((match) => match[1]);
    assert.deepEqual(locations, [`${origin}/`, `${origin}/shortcuts`, `${origin}/privacy`]);
    assert.doesNotMatch(xml, /lastmod/);
  });
});
