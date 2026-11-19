#!/usr/bin/env bash
# Builds Kept with SwiftPM and assembles a signed dist/Kept.app.
#
# Environment:
#   UNIVERSAL=1        build for arm64 and x86_64 (default: this Mac's architecture)
#   SIGN_IDENTITY=…    codesign identity (default: "-", an ad-hoc signature)
#   SIGN_TIMESTAMP=1   add a secure timestamp (needs the network; scripts/package.sh
#                      sets it for real identities, notarization requires it)
#   VERSION=…          CFBundleShortVersionString to stamp, e.g. 1.2.0 or 1.2.0-beta.1
#                      (default: the one in Resources/Info.plist)
#   BUILD_NUMBER=…     CFBundleVersion to stamp (default: `git rev-list --count HEAD`)
#   CONFIGURATION=…    SwiftPM configuration (default: release)
#   BUILD_SYSTEM=…     SwiftPM build system (default: swiftbuild)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Kept"
CONFIGURATION="${CONFIGURATION:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
# Swift Build (SwiftPM's default from Swift 6.4) generates `Bundle.module`
# lookups that search Contents/Resources. The older native build system looks
# only at the .app root (which codesign rejects) and the absolute build folder.
BUILD_SYSTEM="${BUILD_SYSTEM:-swiftbuild}"
INFO_PLIST="$ROOT/Resources/Info.plist"
ENTITLEMENTS="$ROOT/Resources/Kept.entitlements"
ICON="$ROOT/Resources/AppIcon.icns"
APP="$ROOT/dist/$APP_NAME.app"

step() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
plist_value() { /usr/libexec/PlistBuddy -c "Print :$1" "$2"; }

[[ "$(uname -s)" == "Darwin" ]] || die "$APP_NAME.app can only be built on macOS."
command -v swift >/dev/null || die "swift not found. Install Xcode or the Swift toolchain."
command -v codesign >/dev/null || die "codesign not found. Install the Xcode command line tools."
[[ -f "$INFO_PLIST" ]] || die "missing $INFO_PLIST"
[[ -f "$ENTITLEMENTS" ]] || die "missing $ENTITLEMENTS"
plutil -lint "$INFO_PLIST" >/dev/null || die "$INFO_PLIST is not a valid property list."

# The version lives in Resources/Info.plist; VERSION overrides it (dry runs).
# The build number counts commits, so it only grows on master.
VERSION="${VERSION:-$(plist_value CFBundleShortVersionString "$INFO_PLIST")}"
version_pattern='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$'
[[ "$VERSION" =~ $version_pattern ]] ||
    die "VERSION must look like 1.2.0 or 1.2.0-beta.1, not '$VERSION'."
if [[ -z "${BUILD_NUMBER:-}" ]]; then
    if BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null)"; then
        if [[ "$(git -C "$ROOT" rev-parse --is-shallow-repository 2>/dev/null)" == "true" ]]; then
            echo "    note: shallow clone, so build number $BUILD_NUMBER undercounts commits"
        fi
    else
        BUILD_NUMBER="$(plist_value CFBundleVersion "$INFO_PLIST")"
    fi
fi
build_pattern='^[0-9]+(\.[0-9]+){0,2}$'
[[ "$BUILD_NUMBER" =~ $build_pattern ]] ||
    die "BUILD_NUMBER must be up to three dot-separated integers, not '$BUILD_NUMBER'."

build_flags=(--package-path "$ROOT" -c "$CONFIGURATION" --build-system "$BUILD_SYSTEM")
# Name the architectures explicitly: Swift Build's release default is universal.
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCHS="arm64 x86_64"
else
    ARCHS="$(uname -m)"
fi
for arch in $ARCHS; do
    build_flags+=(--arch "$arch")
done

step "Building $APP_NAME $VERSION ($BUILD_NUMBER) for $ARCHS ($CONFIGURATION, $BUILD_SYSTEM)"
swift build "${build_flags[@]}" --product "$APP_NAME"
BIN_DIR="$(swift build "${build_flags[@]}" --show-bin-path)"
EXECUTABLE="$BIN_DIR/$APP_NAME"
if [[ ! -x "$EXECUTABLE" ]]; then
    echo "Executables named $APP_NAME under .build:" >&2
    find "$ROOT/.build" -type f -name "$APP_NAME" -perm -u+x -print >&2 || true
    die "no executable at $EXECUTABLE after the build."
fi

step "Assembling ${APP#"$ROOT"/}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$EXECUTABLE" "$APP/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST" "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
if [[ -f "$ICON" ]]; then
    cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "    no Resources/AppIcon.icns yet; using the generic app icon"
fi
# Dependencies' SwiftPM resource bundles (e.g. KeyboardShortcuts' localizations)
# go in Contents/Resources, where their `Bundle.module` looks inside an app.
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
    echo "    resources: $(basename "$bundle")"
    cp -R "$bundle" "$APP/Contents/Resources/"
done
shopt -u nullglob

BUILT_ARCHS="$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
for arch in $ARCHS; do
    [[ " $BUILT_ARCHS " == *" $arch "* ]] ||
        die "the executable has slices for $BUILT_ARCHS, not $arch."
done

step "Signing (identity: $SIGN_IDENTITY)"
sign_flags=(--force --options runtime -s "$SIGN_IDENTITY")
if [[ "${SIGN_TIMESTAMP:-0}" == "1" && "$SIGN_IDENTITY" != "-" ]]; then
    sign_flags+=(--timestamp)
fi
# Inside out, deepest first: nested code (frameworks, XPC services, helpers,
# loose dylibs) before the app, never --deep, which would sign everything with
# the app's entitlements. Nested code keeps its own entitlements. Kept has no
# nested code yet; SwiftPM's resource bundles hold no code and are sealed as
# the app's resources.
nested_code() {
    find "$APP/Contents" -mindepth 2 \
        \( -path "$APP/Contents/MacOS/$APP_NAME" -prune \) -o \
        \( -type d \( -name '*.framework' -o -name '*.xpc' -o -name '*.app' \
                      -o -name '*.appex' -o -name '*.bundle' \) -print \) -o \
        \( -type f -print \) |
    while IFS= read -r path; do
        if [[ -d "$path" ]]; then
            [[ "$path" == *.bundle && ! -d "$path/Contents/MacOS" ]] && continue
        else
            [[ "$(file -b "$path")" == Mach-O* ]] || continue
        fi
        depth="${path//[^\/]/}"
        printf '%d\t%s\n' "${#depth}" "$path"
    done | sort -rn | cut -f2-
}
while IFS= read -r code; do
    echo "    nested: ${code#"$APP"/}"
    codesign "${sign_flags[@]}" --preserve-metadata=entitlements "$code"
done < <(nested_code)
codesign "${sign_flags[@]}" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict --verbose=2 "$APP"

step "Built ${APP#"$ROOT"/} $VERSION ($BUILD_NUMBER, $BUILT_ARCHS)"
