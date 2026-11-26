// What the build makes of GitHub's latest-release answer: the download
// button only ever offers the repository's own release download.
import assert from 'node:assert/strict';
import { describe, test } from 'node:test';
import { isReleaseDownload, releaseFromGitHub } from '../../src/lib/github-release.ts';

const repoUrl = 'https://github.com/WaseemSabir/Kept';
const dmgUrl = `${repoUrl}/releases/download/v0.2.0/Kept-0.2.0.dmg`;

/** An API answer with one disk image at `url`, and its checksum file. */
function answer(url = dmgUrl): Record<string, unknown> {
  return {
    tag_name: 'v0.2.0',
    published_at: '2026-11-20T10:00:00Z',
    assets: [
      { name: 'Kept-0.2.0.dmg.sha256', browser_download_url: `${repoUrl}/releases/download/v0.2.0/Kept-0.2.0.dmg.sha256`, size: 90 },
      { name: 'Kept-0.2.0.dmg', browser_download_url: url, size: 4_200_000 },
    ],
  };
}

describe('releaseFromGitHub', () => {
  test('reads the version and the disk image', () => {
    assert.deepEqual(releaseFromGitHub(answer(), repoUrl), {
      version: '0.2.0',
      downloadUrl: dmgUrl,
      fileName: 'Kept-0.2.0.dmg',
      size: 4_200_000,
      publishedAt: '2026-11-20T10:00:00Z',
      source: 'github',
    });
  });

  test('says why when the answer isn’t usable', () => {
    assert.throws(() => releaseFromGitHub({ message: 'Not Found' }, repoUrl), /something unexpected/);
    assert.throws(() => releaseFromGitHub({ ...answer(), assets: [] }, repoUrl), /release v0\.2\.0 has no \.dmg/);
  });

  test('refuses a disk image that isn’t the repository’s own release download', () => {
    for (const url of [
      'https://evil.example/Kept-0.2.0.dmg',
      'https://github.com/someone-else/Kept/releases/download/v0.2.0/Kept-0.2.0.dmg',
      'https://github.com/WaseemSabir/Kept-fork/releases/download/v0.2.0/Kept-0.2.0.dmg',
      'http://github.com/WaseemSabir/Kept/releases/download/v0.2.0/Kept-0.2.0.dmg',
      `${repoUrl}/archive/v0.2.0.dmg`,
    ]) {
      assert.throws(() => releaseFromGitHub(answer(url), repoUrl), /isn't a download from https:\/\/github\.com\/WaseemSabir\/Kept\/releases/, url);
    }
  });
});

describe('isReleaseDownload', () => {
  test('a release download of the repository', () => {
    assert.ok(isReleaseDownload(dmgUrl, repoUrl));
  });

  test('not one that only starts like one', () => {
    assert.ok(!isReleaseDownload(`${repoUrl}/releases/download/../../../../evil/x.dmg`, repoUrl), '"../" out of the downloads');
    assert.ok(!isReleaseDownload(`${repoUrl}/releases/download/%2e%2e/%2e%2e/x.dmg`, repoUrl), 'encoded "../"');
    assert.ok(!isReleaseDownload(`${repoUrl}/releases/downloads/x.dmg`, repoUrl));
    assert.ok(!isReleaseDownload('', repoUrl));
  });
});
