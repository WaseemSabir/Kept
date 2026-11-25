// The JSON-LD each page carries: built from the page's own data, claiming
// nothing the README doesn't, and safe inside a <script> element.
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { questions } from '../../src/data/faq.ts';
import { privacyPage, shortcutsPage } from '../../src/data/pages.ts';
import type { Release } from '../../src/data/release.ts';
import { homeGraph, pageGraph, serializeJsonLd, type Graph } from '../../src/lib/structured-data.ts';

const origin = 'https://kept.example';
const release: Release = {
  version: '0.1.0',
  downloadUrl: 'https://github.com/WaseemSabir/Kept/releases/download/v0.1.0/Kept-0.1.0.dmg',
  source: 'github',
};
const graph = homeGraph({
  origin,
  release,
  questions,
  icon: { url: `${origin}/icon-512.png`, width: 512, height: 512 },
  screenshots: [{ url: `${origin}/_astro/a.webp`, width: 1520, height: 1000, caption: 'Searching.' }],
});

const node = (graphToSearch: Graph, type: string): Record<string, unknown> => {
  const found = graphToSearch['@graph'].find((item) => item['@type'] === type);
  if (!found) throw new Error(`No ${type} in the graph`);
  return found;
};

describe('the home page', () => {
  test('describes the website, the app, its source code and the questions', () => {
    assert.equal(graph['@context'], 'https://schema.org');
    assert.deepEqual(
      graph['@graph'].map((item) => item['@type']),
      ['WebSite', 'Organization', 'SoftwareApplication', 'SoftwareSourceCode', 'FAQPage'],
    );
  });

  test('the app: what the README says, and the release the download button points at', () => {
    const app = node(graph, 'SoftwareApplication');
    assert.equal(app.applicationCategory, 'UtilitiesApplication');
    assert.equal(app.operatingSystem, 'macOS 14 or later');
    assert.equal(app.softwareVersion, '0.1.0');
    assert.equal(app.downloadUrl, release.downloadUrl);
    assert.deepEqual(app.offers, { '@type': 'Offer', price: '0', priceCurrency: 'USD' });
    assert.equal(app.isAccessibleForFree, true);
    assert.equal(app.license, 'https://opensource.org/license/mit');
    assert.deepEqual(app.sameAs, ['https://github.com/WaseemSabir/Kept']);
    assert.deepEqual(app.author, { '@id': `${origin}/#contributors` });
    assert.equal(node(graph, 'Organization').name, 'Kept contributors');
  });

  test('claims no ratings, reviews or counts', () => {
    const json = JSON.stringify(graph);
    for (const key of ['aggregateRating', 'review', 'ratingValue', 'interactionStatistic', 'downloads']) {
      assert.ok(!json.includes(`"${key}"`), key);
    }
  });

  test('without a known version, it doesn’t name one', () => {
    const unknown = homeGraph({
      origin,
      release: { downloadUrl: 'https://github.com/WaseemSabir/Kept/releases/latest', source: 'info-plist' },
      questions,
      icon: { url: `${origin}/icon-512.png`, width: 512, height: 512 },
      screenshots: [],
    });
    assert.equal('softwareVersion' in node(unknown, 'SoftwareApplication'), false);
  });

  test('the source code: Swift, MIT, on GitHub', () => {
    const source = node(graph, 'SoftwareSourceCode');
    assert.equal(source.programmingLanguage, 'Swift');
    assert.equal(source.codeRepository, 'https://github.com/WaseemSabir/Kept');
    assert.equal(source.license, 'https://opensource.org/license/mit');
  });

  test('every question, its answer as plain text', () => {
    const faq = node(graph, 'FAQPage');
    const entities = faq.mainEntity as { name: string; acceptedAnswer: { text: string } }[];
    assert.equal(entities.length, questions.length);
    assert.equal(entities[0]?.name, 'What is Kept?');
    for (const entity of entities) {
      assert.doesNotMatch(entity.acceptedAnswer.text, /[{}`]|\*\*/, entity.name);
    }
    assert.match(entities[0]?.acceptedAnswer.text ?? '', /when you press ⇧⌘V,/);
  });
});

describe('other pages', () => {
  test('a WebPage one step down a breadcrumb from the home page', () => {
    for (const page of [shortcutsPage, privacyPage]) {
      const pageData = pageGraph(page, origin);
      const webPage = node(pageData, 'WebPage');
      assert.equal(webPage.url, `${origin}${page.path}`);
      assert.equal(webPage.name, page.title);
      const breadcrumb = node(pageData, 'BreadcrumbList');
      assert.deepEqual(breadcrumb.itemListElement, [
        { '@type': 'ListItem', position: 1, name: 'Kept', item: `${origin}/` },
        { '@type': 'ListItem', position: 2, name: page.name, item: `${origin}${page.path}` },
      ]);
    }
  });
});

describe('serializing', () => {
  test('no string can end the <script> element it sits in', () => {
    const hostile: Graph = { '@context': 'https://schema.org', '@graph': [{ name: '</script><script>alert(1)</script><!--' }] };
    const json = serializeJsonLd(hostile);
    assert.ok(!json.includes('<'));
    assert.deepEqual(JSON.parse(json), hostile);
  });
});
