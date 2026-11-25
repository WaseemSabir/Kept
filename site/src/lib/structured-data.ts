// Structured data (schema.org JSON-LD): one @graph per page, built from the
// data the page renders, so it can't say something the page doesn't. The
// home page describes the site, the app, its source code and the questions;
// other pages are a WebPage in a breadcrumb trail. Nothing here may claim
// more than the README does: no ratings, reviews or download counts.

import { authorName, language, minimumMacOS, mitLicenseUrl, name, repoUrl } from '../config.ts';
import type { Question } from '../data/faq.ts';
import { home, type Page } from '../data/pages.ts';
import type { Release } from '../data/release.ts';
import { toPlainText } from './inline.ts';

type Node = Record<string, unknown>;

export interface Graph {
  '@context': 'https://schema.org';
  '@graph': Node[];
}

/** An image for structured data, with an absolute address. */
export interface ImageFile {
  url: string;
  width: number;
  height: number;
  caption?: string;
}

export interface HomeGraphInput {
  /** The site's origin: "https://kept.waseemsabir.com". */
  origin: string;
  release: Release;
  questions: readonly Question[];
  /** The app icon, square. */
  icon: ImageFile;
  screenshots: readonly ImageFile[];
}

/** Stable identifiers, so nodes on different pages can refer to each other. */
export const ids = {
  website: (origin: string) => `${new URL('/', origin).href}#website`,
  app: (origin: string) => `${new URL('/', origin).href}#app`,
  source: (origin: string) => `${new URL('/', origin).href}#source`,
  contributors: (origin: string) => `${new URL('/', origin).href}#contributors`,
  webpage: (url: string) => `${url}#webpage`,
  breadcrumb: (url: string) => `${url}#breadcrumb`,
};

const imageObject = (image: ImageFile): Node => ({
  '@type': 'ImageObject',
  url: image.url,
  contentUrl: image.url,
  width: image.width,
  height: image.height,
  ...(image.caption ? { caption: image.caption } : {}),
});

/** The home page: the website, the app, its source code, and the questions it answers. */
export function homeGraph({ origin, release, questions, icon, screenshots }: HomeGraphInput): Graph {
  const url = new URL(home.path, origin).href;
  const contributors = { '@id': ids.contributors(origin) };
  return {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'WebSite',
        '@id': ids.website(origin),
        url,
        name,
        description: home.description,
        inLanguage: language,
        publisher: contributors,
      },
      {
        '@type': 'Organization',
        '@id': ids.contributors(origin),
        name: authorName,
        url: repoUrl,
      },
      {
        '@type': 'SoftwareApplication',
        '@id': ids.app(origin),
        name,
        description: home.description,
        url,
        applicationCategory: 'UtilitiesApplication',
        operatingSystem: `macOS ${minimumMacOS.version} or later`,
        ...(release.version ? { softwareVersion: release.version } : {}),
        downloadUrl: release.downloadUrl,
        offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
        isAccessibleForFree: true,
        license: mitLicenseUrl,
        image: imageObject(icon),
        screenshot: screenshots.map(imageObject),
        author: contributors,
        publisher: contributors,
        sameAs: [repoUrl],
      },
      {
        '@type': 'SoftwareSourceCode',
        '@id': ids.source(origin),
        name,
        url: repoUrl,
        codeRepository: repoUrl,
        programmingLanguage: 'Swift',
        license: mitLicenseUrl,
        author: contributors,
        targetProduct: { '@id': ids.app(origin) },
      },
      {
        '@type': 'FAQPage',
        '@id': ids.webpage(url),
        url,
        name: home.title,
        description: home.description,
        inLanguage: language,
        isPartOf: { '@id': ids.website(origin) },
        about: { '@id': ids.app(origin) },
        mainEntity: questions.map((item) => ({
          '@type': 'Question',
          name: item.question,
          acceptedAnswer: { '@type': 'Answer', text: item.answer.map(toPlainText).join('\n\n') },
        })),
      },
    ],
  };
}

/** Any other indexable page: a WebPage, one step down from the home page. */
export function pageGraph(page: Page, origin: string): Graph {
  const homeUrl = new URL(home.path, origin).href;
  const url = new URL(page.path, origin).href;
  return {
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'WebPage',
        '@id': ids.webpage(url),
        url,
        name: page.title,
        description: page.description,
        inLanguage: language,
        isPartOf: { '@id': ids.website(origin) },
        about: { '@id': ids.app(origin) },
        breadcrumb: { '@id': ids.breadcrumb(url) },
      },
      {
        '@type': 'BreadcrumbList',
        '@id': ids.breadcrumb(url),
        itemListElement: [
          { '@type': 'ListItem', position: 1, name: home.name, item: homeUrl },
          { '@type': 'ListItem', position: 2, name: page.name, item: url },
        ],
      },
    ],
  };
}

/**
 * JSON for a <script type="application/ld+json"> element. "<" is written as
 * <, so no string in it can close the element ("</script>") or open a
 * comment; JSON parsers read it back as "<".
 */
export function serializeJsonLd(graph: Graph): string {
  return JSON.stringify(graph).replaceAll('<', '\\u003c');
}
