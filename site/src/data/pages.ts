// The site's pages: where each one lives, what search results and link
// previews show for it (title ≤ 60 characters, description ≤ 155), its
// Markdown twin, and the prose that is the page's own rather than another
// data module's. Base.astro, the sitemap, llms.txt, the Markdown twins and
// the structured data all read these entries, so each string has one home.
//
// Prose uses the inline convention in src/lib/inline.ts. Every claim is
// backed by README.md, docs/DESIGN.md or SECURITY.md.

import { contributingUrl, issuesUrl, repoUrl, roadmapUrl, securityUrl } from '../config.ts';

export interface Page {
  id: 'home' | 'shortcuts' | 'privacy' | 'not-found';
  /** The page's address, as its canonical link has it: "/" or "/shortcuts". */
  path: string;
  /** Its name in breadcrumbs and lists of pages. */
  name: string;
  /** The <title>, and og:title. */
  title: string;
  /** The meta description, and og:description. */
  description: string;
  /**
   * Listed by search engines: a canonical link, a sitemap entry, a Markdown
   * twin and structured data. False for the 404.
   */
  indexable: boolean;
  /**
   * The Markdown twin's address (llmstxt.org): the page's address plus
   * ".md", "/index.html.md" for the home page.
   */
  markdownPath?: string;
}

export const home = {
  id: 'home',
  path: '/',
  name: 'Kept',
  title: 'Kept: a keyboard-first clipboard manager for the Mac',
  description:
    'Kept is a free, open-source clipboard manager for the Mac. Press ⇧⌘V in any app, type a few letters ' +
    'and press ⏎ to paste what you copied earlier.',
  indexable: true,
  markdownPath: '/index.html.md',
} as const satisfies Page;

export const shortcutsPage = {
  id: 'shortcuts',
  path: '/shortcuts',
  name: 'Keyboard shortcuts',
  title: 'Keyboard shortcuts – Kept, a clipboard manager for the Mac',
  description:
    'Every keyboard shortcut in Kept: ⇧⌘V opens it, ⏎ pastes, ⌥⏎ pastes as plain text, ⌘⏎ copies, ' +
    '⌘1–⌘9 paste the first nine clips and ⌘P pins a clip.',
  indexable: true,
  markdownPath: '/shortcuts.md',
} as const satisfies Page;

export const privacyPage = {
  id: 'privacy',
  path: '/privacy',
  name: 'Privacy',
  title: 'Privacy – Kept, a clipboard manager for the Mac',
  description:
    'Your clipboard history stays on your Mac: Kept has no network access, accounts, sync or telemetry, ' +
    'and skips secrets and what password managers copy.',
  indexable: true,
  markdownPath: '/privacy.md',
} as const satisfies Page;

export const notFoundPage = {
  id: 'not-found',
  path: '/404',
  name: 'Page not found',
  title: 'Page not found – Kept',
  description: 'This page isn’t on Kept’s website.',
  indexable: false,
} as const satisfies Page;

/** The pages search engines list, in the order the site presents them. */
export const indexedPages: readonly Page[] = [home, shortcutsPage, privacyPage];

// MARK: The home page

/** "Open source", near the end of the home page. */
export const openSource: string[] = [
  `Kept is free and open source under the MIT license, and all of its code is on [GitHub](${repoUrl}).`,
  'It’s at 0.1, its first version. History, search, pasting, pins and Settings work, but few people have ' +
    `used it yet: expect rough edges, and please [report them](${issuesUrl}).`,
  `The [roadmap](${roadmapUrl}) says what’s done and what’s next, and the ` +
    `[contributing guide](${contributingUrl}) explains how to build and test Kept and where things go.`,
];

// MARK: Keyboard shortcuts

export const shortcutsIntro =
  'Kept is made to be used from the keyboard. In the panel the search field always has the keyboard, so ' +
  'typing searches and the keys below act on the selected clip.';

/** Under "Global". */
export const globalShortcutsNote = 'These work in any app. Change them in Settings › Shortcuts.';

/** After the panel's shortcuts. */
export const panelShortcutsNote =
  'With **Always paste as plain text** turned on in Settings › General, {⏎} and {⌥⏎} swap. Right-click any ' +
  'clip for the same actions.';

// MARK: Privacy

export const privacyIntro =
  'What you copy is often private: messages, addresses, code, things you meant to keep to yourself. Kept ' +
  'keeps it on your Mac and nowhere else, and leaves you in charge of what it keeps.';

/** "On this website". */
export const websitePrivacy: string[] = [
  'This site sets no cookies, runs no analytics and loads nothing from third parties: no fonts, scripts or ' +
    'images from anyone else. Its pages are static files.',
  'It’s hosted on Vercel, which, like any host, keeps logs of the requests it serves. The download button ' +
    `and the GitHub links take you to [GitHub](${repoUrl}), where GitHub’s own privacy terms apply.`,
];

/** "Report a security issue", from SECURITY.md. */
export const reportingSecurity: string[] = [
  'Please don’t report security or privacy issues in public GitHub issues. Report them privately instead, ' +
    'with GitHub’s private vulnerability reporting: on the repository’s Security tab, choose Advisories, ' +
    'then Report a vulnerability.',
  `The [security policy](${securityUrl}) says which versions get fixes and what to include in a report.`,
];
