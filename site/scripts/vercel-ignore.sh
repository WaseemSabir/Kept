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
#   - anything the site is built from changed since then: site/, the
#     screenshots (docs/images), the icon (Resources/Icon) or the version
#     (Resources/Info.plist).
# Otherwise (a push that only touched the app's code, say) it skips.
#
# POSIX sh, and independent of the directory it's run from: paths come
# from the script's own location. Prints one line saying what it decided and why.

build() {
  echo "vercel-ignore: build: $1"
  exit 1
}

skip() {
  echo "vercel-ignore: skip: $1"
  exit 0
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
