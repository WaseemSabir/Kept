// The release the download button points at, worked out once per build.
//
// First choice: GitHub's latest release and its disk image. Anything going
// wrong there (the repository is private, a rate limit, no network, a
// release without a .dmg) falls back to the version in Resources/Info.plist
// and the latest-release page. The build never fails over this; it logs one
// line saying which path it took.

import infoPlist from '../../../Resources/Info.plist?raw';
import { latestReleaseUrl, repoUrl } from '../config';

export interface Release {
  /** "0.1.0": the tag without its "v", or Info.plist's version. */
  version?: string;
  /** The disk image itself, or the latest-release page. */
  downloadUrl: string;
  /** "Kept-0.1.0.dmg", when the disk image is known. */
  fileName?: string;
  /** The disk image's size in bytes. */
  size?: number;
  /** When the release was published (ISO 8601). */
  publishedAt?: string;
  source: 'github' | 'info-plist';
}

const apiUrl = `${repoUrl.replace('https://github.com/', 'https://api.github.com/repos/')}/releases/latest`;
const timeoutMs = 5000;

let pending: Promise<Release> | undefined;

/** The latest release. Every caller in a build shares one request. */
export function getRelease(): Promise<Release> {
  pending ??= load();
  return pending;
}

async function load(): Promise<Release> {
  try {
    const release = await fromGitHub();
    console.info(`[kept] Download: GitHub's latest release, ${release.fileName} (${release.version}).`);
    return release;
  } catch (error) {
    const version = versionFromInfoPlist();
    const reason = error instanceof Error ? error.message : String(error);
    console.info(
      `[kept] Download: the releases page, version ${version ?? 'unknown'} from Info.plist ` +
        `(GitHub's latest release isn't available: ${reason}).`,
    );
    return { version, downloadUrl: latestReleaseUrl, source: 'info-plist' };
  }
}

async function fromGitHub(): Promise<Release> {
  const headers: Record<string, string> = {
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };
  const token = buildEnvironment().GITHUB_TOKEN;
  if (token) headers.Authorization = `Bearer ${token}`;

  const response = await fetch(apiUrl, { headers, signal: AbortSignal.timeout(timeoutMs) });
  if (!response.ok) throw new Error(`the API answered ${response.status}`);

  const data: unknown = await response.json();
  if (!isGitHubRelease(data)) throw new Error('the API answered with something unexpected');
  const diskImage = data.assets.find((asset) => asset.name.endsWith('.dmg'));
  if (!diskImage) throw new Error(`release ${data.tag_name} has no .dmg`);

  return {
    version: data.tag_name.replace(/^v/, ''),
    downloadUrl: diskImage.browser_download_url,
    fileName: diskImage.name,
    size: diskImage.size,
    publishedAt: data.published_at ?? undefined,
    source: 'github',
  };
}

/**
 * The build's environment variables, read when the build runs (not inlined
 * like import.meta.env), typed without needing @types/node.
 */
function buildEnvironment(): Record<string, string | undefined> {
  return (globalThis as { process?: { env?: Record<string, string | undefined> } }).process?.env ?? {};
}

/** CFBundleShortVersionString, the version the app shows in About. */
function versionFromInfoPlist(): string | undefined {
  return /<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/.exec(infoPlist)?.[1]?.trim();
}

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
