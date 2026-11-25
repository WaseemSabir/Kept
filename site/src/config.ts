// Facts about Kept that more than one page uses. Every claim on the site
// must be backed by the repository's README.md, docs/DESIGN.md or
// docs/ROADMAP.md; when those change, change this file with them.

/** The canonical production address. `astro.config.mjs` reads it too. */
export const productionUrl = 'https://kept.waseemsabir.com';

export const name = 'Kept';
export const tagline = 'A clipboard history for the Mac';
/** The home page's <title>. Other pages are "<Page> – Kept" (see pageTitle). */
export const homeTitle = 'Kept: a clipboard history for the Mac';
export const pageTitle = (page: string): string => `${page} – ${name}`;
export const description =
  'Kept is a free, open-source clipboard history for the Mac. Press ⇧⌘V in any app, ' +
  'type a few letters, press ⏎, and what you copied is back where you were typing.';
/** The home page's opening paragraph, in the inline convention of src/lib/inline.ts. */
export const lede =
  'Kept is a clipboard history for the Mac. Press {⇧⌘V} in any app, type a few letters, press {⏎}, ' +
  'and what you copied an hour ago is back where you were typing. Native, private and open source.';

export const repoUrl = 'https://github.com/WaseemSabir/Kept';
export const releasesUrl = `${repoUrl}/releases`;
export const latestReleaseUrl = `${repoUrl}/releases/latest`;
export const issuesUrl = `${repoUrl}/issues`;

/** Files in the repository, as GitHub shows them (default branch). */
export const repoFile = (path: string): string => `${repoUrl}/blob/master/${path}`;
export const roadmapUrl = repoFile('docs/ROADMAP.md');
export const contributingUrl = repoFile('CONTRIBUTING.md');
export const licenseUrl = repoFile('LICENSE');
export const securityUrl = repoFile('SECURITY.md');

/** `LSMinimumSystemVersion` in Resources/Info.plist. */
export const minimumMacOS = { version: '14', name: 'Sonoma' } as const;

/** The global shortcut that opens Kept, as recorded by default. */
export const openShortcut = '⇧⌘V';
