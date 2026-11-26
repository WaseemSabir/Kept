#!/bin/sh
# Vercel's "Ignored Build Step" for the site (vercel.json › ignoreCommand):
# decides whether a push needs a new deployment. Exit 0 skips the build,
# exit 1 builds. vercel.json runs it as `sh scripts/vercel-ignore.sh || exit 1`,
# so a missing script, or any exit but 0, builds too: when in doubt, build.
#
# It builds when:
#   - there's no previous deployment of this branch (VERCEL_GIT_PREVIOUS_SHA unset);
#   - the previous deployment is of this very commit: a redeploy, or a deploy
#     hook run after a new app release so the download button picks it up;
#   - the previous commit isn't in the (shallow) clone, so there's nothing to compare;
#   - for production only (VERCEL_ENV=production): the live site states a
#     different version than GitHub's latest release. The release workflow's
#     deploy hook builds the head of master, which may be a commit after the
#     last deployment that only touched the app; without this the diff below
#     would skip it and the site would go on offering the old version. The
#     live version is the softwareVersion in the home page's JSON-LD, the
#     latest release the tag GitHub's /releases/latest redirects to (no API,
#     so no rate limit; a private repository answers 404). Only two versions
#     that were both found and differ build: if either lookup fails (no
#     curl, no network, a timeout, nothing found) the log line says so and
#     the diff decides, as it does for previews;
#   - anything the site is built from changed since then: site/, the
#     screenshots (docs/images), the icon (Resources/Icon) or the version
#     (Resources/Info.plist).
# Otherwise (a push that only touched the app's code, say) it skips.
#
# POSIX sh, and independent of the directory it's run from: paths come
# from the script's own location. Prints one line saying what it decided and why.

# The production site and the repository. They mirror productionUrl and
# repoUrl in site/src/config.ts; `npm run check:dist` fails if they don't.
site_url='https://kept.waseemsabir.com'
repo_url='https://github.com/WaseemSabir/Kept'

# How the version check came out, when it didn't decide: added to the log line.
note=''

build() {
  echo "vercel-ignore: build: $1${note:+ ($note)}"
  exit 1
}

skip() {
  echo "vercel-ignore: skip: $1${note:+ ($note)}"
  exit 0
}

# The version the live site states: "softwareVersion":"0.1.0" in its JSON-LD.
live_version() {
  curl --silent --fail --location --max-time 5 "$site_url/" 2>/dev/null |
    sed -n 's/.*"softwareVersion"[[:space:]]*:[[:space:]]*"\([0-9A-Za-z.+_-]*\)".*/\1/p' |
    sed -n 1p
}

# GitHub's latest release, from where /releases/latest redirects:
# Location: https://github.com/owner/repo/releases/tag/v0.1.0 → 0.1.0.
released_version() {
  location=$(curl --silent --head --max-time 5 "$repo_url/releases/latest" 2>/dev/null |
    tr -d '\r' |
    sed -n 's/^[Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]:[[:space:]]*//p' |
    sed -n 1p)
  case $location in
    "$repo_url/releases/tag/"?*) ;;
    *) return 0 ;;
  esac
  tag=${location#"$repo_url/releases/tag/"}
  version=${tag#v}
  case $version in
    '' | *[!0-9A-Za-z.+_-]*) ;;
    *) echo "$version" ;;
  esac
}

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd) || build "can't find the script's directory"
site_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd) || build "can't find the site's directory"
command -v git >/dev/null 2>&1 || build "git isn't available"
repo_dir=$(git -C "$site_dir" rev-parse --show-toplevel 2>/dev/null) || build "$site_dir isn't in a Git checkout"

previous=${VERCEL_GIT_PREVIOUS_SHA:-}
current=${VERCEL_GIT_COMMIT_SHA:-}

[ -n "$previous" ] || build "no previous deployment of this branch to compare with"
[ "$previous" != "$current" ] || build "redeploying the same commit ($previous)"
git -C "$repo_dir" cat-file -e "$previous^{commit}" 2>/dev/null ||
  build "the previous deployment's commit $previous isn't in this clone"

if [ "${VERCEL_ENV:-}" = production ]; then
  if ! command -v curl >/dev/null 2>&1; then
    note="versions not compared: curl isn't available"
  else
    live=$(live_version)
    if [ -z "$live" ]; then
      note="versions not compared: no softwareVersion from $site_url"
    else
      released=$(released_version)
      if [ -z "$released" ]; then
        note="versions not compared: no latest release from $repo_url/releases/latest"
      elif [ "$live" != "$released" ]; then
        build "the live site says $live, GitHub's latest release is $released"
      else
        note="the live site and GitHub's latest release are both $live"
      fi
    fi
  fi
fi

# The site's directory as Git names it, from the repository's root.
site_path=$(git -C "$site_dir" rev-parse --show-prefix 2>/dev/null) || build "can't place $site_dir in the repository"
site_path=${site_path%/}
[ -n "$site_path" ] || site_path=.

git -C "$repo_dir" diff --quiet "$previous" HEAD -- \
  "$site_path" docs/images Resources/Icon Resources/Info.plist
status=$?
case $status in
  0) skip "nothing the site is built from changed since $previous" ;;
  1) build "the site, its images, the icon or the version changed since $previous" ;;
  *) build "git diff failed (exit $status)" ;;
esac
