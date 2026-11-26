// GitHub's answer for the latest release (GET /repos/{owner}/{repo}/releases/latest),
// read into the release the download button offers. Pure, so it's tested
// without a network; src/data/release.ts asks GitHub and falls back on any
// Error thrown here, whose message says why.

import type { Release } from '../data/release.ts';

interface GitHubRelease {
  tag_name: string;
  published_at: string | null;
  assets: { name: string; browser_download_url: string; size: number }[];
}

function isGitHubRelease(value: unknown): value is GitHubRelease {
  if (typeof value !== 'object' || value === null) return false;
  const release = value as Partial<GitHubRelease>;
  return (
    typeof release.tag_name === 'string' &&
    Array.isArray(release.assets) &&
    release.assets.every(
      (asset) =>
        typeof asset?.name === 'string' &&
        typeof asset.browser_download_url === 'string' &&
        typeof asset.size === 'number',
    )
  );
}

/**
 * Whether an address is one of the repository's release downloads,
 * "https://github.com/owner/repo/releases/download/…", as written and as a
 * browser resolves it (no "../" out of there).
 */
export function isReleaseDownload(address: string, repoUrl: string): boolean {
  const downloads = `${repoUrl}/releases/download/`;
  if (!address.startsWith(downloads)) return false;
  try {
    return new URL(address).href.startsWith(downloads);
  } catch {
    return false;
  }
}

/**
 * The release in the API's answer: its tag without the "v", and its disk
 * image. Throws when the answer isn't a release, the release has no .dmg,
 * or the .dmg's address isn't the repository's own release download.
 */
export function releaseFromGitHub(data: unknown, repoUrl: string): Release {
  if (!isGitHubRelease(data)) throw new Error('the API answered with something unexpected');
  const diskImage = data.assets.find((asset) => asset.name.endsWith('.dmg'));
  if (!diskImage) throw new Error(`release ${data.tag_name} has no .dmg`);
  if (!isReleaseDownload(diskImage.browser_download_url, repoUrl)) {
    throw new Error(
      `release ${data.tag_name}'s disk image isn't a download from ${repoUrl}/releases: ` +
        JSON.stringify(diskImage.browser_download_url.slice(0, 200)),
    );
  }
  return {
    version: data.tag_name.replace(/^v/, ''),
    downloadUrl: diskImage.browser_download_url,
    fileName: diskImage.name,
    size: diskImage.size,
    publishedAt: data.published_at ?? undefined,
    source: 'github',
  };
}
