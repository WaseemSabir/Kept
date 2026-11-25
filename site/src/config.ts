// Facts about Kept that more than one page uses. Every claim on the site
// must be backed by the repository's README.md, docs/DESIGN.md or
// docs/ROADMAP.md; when those change, change this file with them.

/** The canonical production address. `astro.config.mjs` reads it too. */
export const productionUrl = 'https://kept.waseemsabir.com';

export const name = 'Kept';
/** Who makes Kept, as structured data names them. */
export const authorName = 'Kept contributors';
/** The language and region of the copy, for `<html lang>` and og:locale. */
export const language = 'en';
export const locale = 'en_US';

/** The home page's opening paragraph, in the inline convention of src/lib/inline.ts. */
export const lede =
  'Kept is a clipboard history for the Mac. Press {⇧⌘V} in any app, type a few letters, press {⏎}, ' +
  'and what you copied an hour ago is back where you were typing. Native, private and open source.';

export const repoUrl = 'https://github.com/WaseemSabir/Kept';
export const releasesUrl = `${repoUrl}/releases`;
export const latestReleaseUrl = `${repoUrl}/releases/latest`;
export const issuesUrl = `${repoUrl}/issues`;
/** `git clone` address. */
export const cloneUrl = `${repoUrl}.git`;

/** Files in the repository, as GitHub shows them (default branch). */
export const repoFile = (path: string): string => `${repoUrl}/blob/master/${path}`;
export const readmeUrl = repoFile('README.md');
export const roadmapUrl = repoFile('docs/ROADMAP.md');
export const contributingUrl = repoFile('CONTRIBUTING.md');
export const licenseUrl = repoFile('LICENSE');
export const securityUrl = repoFile('SECURITY.md');
/** The license itself, for structured data: Kept is MIT licensed (LICENSE). */
export const mitLicenseUrl = 'https://opensource.org/license/mit';

/** `LSMinimumSystemVersion` in Resources/Info.plist. */
export const minimumMacOS = { version: '14', name: 'Sonoma' } as const;

/** The global shortcut that opens Kept, as recorded by default. */
export const openShortcut = '⇧⌘V';

/** The `page` token (docs/DESIGN.md › Website › Color): theme-color and the manifest. */
export const pageColor = { light: '#f6f6f4', dark: '#17181c' } as const;
