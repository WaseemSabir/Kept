// The site as Markdown, for assistants: each page's Markdown twin
// (/index.html.md, /shortcuts.md, /privacy.md), llms.txt (llmstxt.org) and
// llms-full.txt, everything in one document. Built from the same data
// modules as the pages, so they say what the pages say.
//
// The section headings repeat the pages' own; `npm run check:dist` fails if
// a twin has a heading its page doesn't.

import {
  latestReleaseUrl,
  lede,
  licenseUrl,
  minimumMacOS,
  name,
  readmeUrl,
  releasesUrl,
  repoUrl,
  roadmapUrl,
  securityUrl,
} from '../config.ts';
import { questions } from '../data/faq.ts';
import { features } from '../data/features.ts';
import { installNotes, installSteps, requirement } from '../data/install.ts';
import {
  globalShortcutsNote,
  home,
  openSource,
  panelShortcutsNote,
  privacyIntro,
  privacyPage,
  reportingSecurity,
  shortcutsIntro,
  shortcutsPage,
  websitePrivacy,
  type Page,
} from '../data/pages.ts';
import { privacy } from '../data/privacy.ts';
import type { Release } from '../data/release.ts';
import { essentialShortcuts, globalShortcuts, panelShortcuts, type Shortcut } from '../data/shortcuts.ts';
import { toMarkdown, type MarkdownOptions } from './inline.ts';
import { blocks, document, factList, figure, heading, linkList, numberedList, paragraphs, table } from './markdown.ts';

export interface SiteContext {
  /** The site's origin, "https://kept.waseemsabir.com": links are absolute, for text read out of context. */
  origin: string;
  release: Release;
}

/** A screenshot as the home page shows it, with an absolute address. */
export interface ScreenshotFile {
  url: string;
  alt: string;
  caption: string;
}

const markdownOptions = (context: SiteContext): MarkdownOptions => ({ base: context.origin });
const pageUrl = (context: SiteContext, page: Page): string => new URL(page.path, context.origin).href;
const markdownUrl = (context: SiteContext, page: Page): string =>
  new URL(page.markdownPath ?? page.path, context.origin).href;

// MARK: Pieces the documents share

/** "Version 0.1.0 for macOS 14 or later. Free and open source.", as beside the download button. */
function downloadSentence(release: Release): string {
  const version = release.version ? `Version ${release.version}` : 'The latest version';
  return `${version} for macOS ${minimumMacOS.version} or later. Free and open source.`;
}

function downloadLine(context: SiteContext): string {
  return `[Download Kept](${context.release.downloadUrl}). ${downloadSentence(context.release)}`;
}

function shortcutTable(items: readonly Shortcut[], options: MarkdownOptions): string {
  return table(
    ['Keys', 'Action'],
    items.map((shortcut) => [toMarkdown(shortcut.keys, options), toMarkdown(shortcut.action, options)]),
  );
}

/** "Install Kept": the requirement, the steps, and what to do when macOS gets in the way. */
function installSection(context: SiteContext): string {
  const options = markdownOptions(context);
  return blocks(
    heading(2, 'Install Kept'),
    requirement,
    numberedList(installSteps(context.release), options),
    ...installNotes.map((note) => blocks(heading(3, note.title), paragraphs(note.paragraphs, options))),
  );
}

/** "Questions": every question, each answer in full. */
function questionsSection(context: SiteContext): string {
  const options = markdownOptions(context);
  return blocks(
    heading(2, 'Questions'),
    ...questions.map((item) => blocks(heading(3, item.question), paragraphs(item.answer, options))),
  );
}

/**
 * What Kept is, in one paragraph of facts, for llms.txt and llms-full.txt.
 * Every claim is the README's or already on the site (faq.ts).
 */
function aboutKept(context: SiteContext): string {
  const version = context.release.version
    ? ` The current version is ${context.release.version}.`
    : '';
  return toMarkdown(
    'Kept keeps what you copy (text, rich text, links, images, files and colors) and brings it back when ' +
      'you press {⇧⌘V} in any app: type a few letters to find a clip and press {⏎} to paste it where you ' +
      'were typing. Every action in the panel has a key. ' +
      `It needs macOS ${minimumMacOS.version} ${minimumMacOS.name} or later and runs natively on Macs with ` +
      'Apple silicon and on Intel Macs. Your history stays on your Mac: Kept runs in the App Sandbox ' +
      'without network access and has no accounts, no sync and no telemetry. It’s free and open source ' +
      `under the MIT license.${version}`,
    markdownOptions(context),
  );
}

// MARK: The Markdown twins

/** /index.html.md: the home page. */
export function homeMarkdown(context: SiteContext, screenshots: readonly ScreenshotFile[]): string {
  const options = markdownOptions(context);
  return document(
    heading(1, name),
    toMarkdown(lede, options),
    `${downloadLine(context)} [Source on GitHub](${repoUrl}).`,
    heading(2, 'What Kept does'),
    factList(features, options),
    heading(2, 'Keyboard shortcuts'),
    shortcutTable(essentialShortcuts, options),
    `[All shortcuts](${pageUrl(context, shortcutsPage)})`,
    heading(2, 'Privacy'),
    factList(
      privacy.map(({ label, summary }) => ({ label, value: summary })),
      options,
    ),
    `[Privacy in detail](${pageUrl(context, privacyPage)})`,
    screenshots.length > 0 && heading(2, 'Screenshots'),
    ...screenshots.map((shot) => figure(shot.url, shot.alt, shot.caption)),
    installSection(context),
    questionsSection(context),
    heading(2, 'Open source'),
    paragraphs(openSource, options),
    heading(2, 'Try Kept'),
    downloadLine(context),
  );
}

/** /shortcuts.md */
export function shortcutsMarkdown(context: SiteContext): string {
  const options = markdownOptions(context);
  return document(
    heading(1, 'Keyboard shortcuts'),
    toMarkdown(shortcutsIntro, options),
    heading(2, 'Global'),
    toMarkdown(globalShortcutsNote, options),
    shortcutTable(globalShortcuts, options),
    heading(2, 'In the panel'),
    shortcutTable(panelShortcuts, options),
    toMarkdown(panelShortcutsNote, options),
  );
}

/** /privacy.md */
export function privacyMarkdown(context: SiteContext): string {
  const options = markdownOptions(context);
  return document(
    heading(1, 'Privacy'),
    toMarkdown(privacyIntro, options),
    heading(2, 'In the app'),
    factList(
      privacy.map(({ label, detail }) => ({ label, value: detail })),
      options,
    ),
    heading(2, 'On this website'),
    paragraphs(websitePrivacy, options),
    heading(2, 'Report a security issue'),
    paragraphs(reportingSecurity, options),
  );
}

// MARK: llms.txt

/** /llms.txt, in the llmstxt.org format: a name, a summary, key facts, then links with a note each. */
export function llmsTxt(context: SiteContext): string {
  return document(
    heading(1, name),
    `> ${home.description}`,
    aboutKept(context),
    heading(2, 'Website'),
    linkList([
      {
        name: home.name,
        url: markdownUrl(context, home),
        note: 'What Kept does, the main shortcuts, privacy in short, how to install it, and answers to common questions.',
      },
      {
        name: shortcutsPage.name,
        url: markdownUrl(context, shortcutsPage),
        note: 'Every keyboard shortcut, global and in the panel.',
      },
      {
        name: privacyPage.name,
        url: markdownUrl(context, privacyPage),
        note: 'What Kept keeps, where, what it never saves, and how to report a security issue.',
      },
    ]),
    heading(2, 'Project'),
    linkList([
      { name: 'Source code', url: repoUrl, note: 'Kept’s repository on GitHub: Swift, MIT license.' },
      { name: 'README', url: readmeUrl, note: 'Features, shortcuts, installing, privacy and building from source.' },
      { name: 'Releases', url: releasesUrl, note: 'Every version, with its disk image to download.' },
      { name: 'Roadmap', url: roadmapUrl, note: 'What’s done and what’s next.' },
      { name: 'Security policy', url: securityUrl, note: 'Which versions get fixes, and how to report a vulnerability privately.' },
    ]),
    heading(2, 'Optional'),
    linkList([
      {
        name: 'The whole site in one file',
        url: new URL('/llms-full.txt', context.origin).href,
        note: 'Every page above as one Markdown document.',
      },
    ]),
  );
}

/** /llms-full.txt: the whole site as one Markdown document. */
export function llmsFullTxt(context: SiteContext): string {
  const options = markdownOptions(context);
  return document(
    heading(1, name),
    `> ${home.description}`,
    aboutKept(context),
    `This is everything on [Kept’s website](${pageUrl(context, home)}) in one document. The source code is [on GitHub](${repoUrl}).`,
    heading(2, 'What Kept does'),
    factList(features, options),
    heading(2, 'Keyboard shortcuts'),
    toMarkdown(shortcutsIntro, options),
    heading(3, 'Global'),
    toMarkdown(globalShortcutsNote, options),
    shortcutTable(globalShortcuts, options),
    heading(3, 'In the panel'),
    shortcutTable(panelShortcuts, options),
    toMarkdown(panelShortcutsNote, options),
    heading(2, 'Privacy'),
    toMarkdown(privacyIntro, options),
    factList(
      privacy.map(({ label, detail }) => ({ label, value: detail })),
      options,
    ),
    heading(3, 'On this website'),
    paragraphs(websitePrivacy, options),
    heading(3, 'Report a security issue'),
    paragraphs(reportingSecurity, options),
    installSection(context),
    questionsSection(context),
    heading(2, 'Download'),
    downloadLine(context),
    `Every release is on the [releases page](${releasesUrl}); [the latest one](${latestReleaseUrl}) is always at the same address.`,
    heading(2, 'Open source and license'),
    paragraphs(openSource, options),
    `Kept is released under the [MIT license](${licenseUrl}).`,
  );
}
