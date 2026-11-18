#!/usr/bin/env bash
# Builds Kept with SwiftPM and assembles a signed dist/Kept.app.
#
# Environment:
#   UNIVERSAL=1        build for arm64 and x86_64 (default: this Mac's architecture)
#   SIGN_IDENTITY=…    codesign identity (default: "-", an ad-hoc signature)
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

[[ "$(uname -s)" == "Darwin" ]] || die "$APP_NAME.app can only be built on macOS."
command -v swift >/dev/null || die "swift not found. Install Xcode or the Swift toolchain."
command -v codesign >/dev/null || die "codesign not found. Install the Xcode command line tools."
[[ -f "$INFO_PLIST" ]] || die "missing $INFO_PLIST"
[[ -f "$ENTITLEMENTS" ]] || die "missing $ENTITLEMENTS"
plutil -lint "$INFO_PLIST" >/dev/null || die "$INFO_PLIST is not a valid property list."

build_flags=(--package-path "$ROOT" -c "$CONFIGURATION" --build-system "$BUILD_SYSTEM")
# Name the architectures explicitly: Swift Build's release default is universal.
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    build_flags+=(--arch arm64 --arch x86_64)
else
    build_flags+=(--arch "$(uname -m)")
fi

step "Building $APP_NAME ($CONFIGURATION, $BUILD_SYSTEM)"
swift build "${build_flags[@]}" --product "$APP_NAME"
BIN_DIR="$(swift build "${build_flags[@]}" --show-bin-path)"
EXECUTABLE="$BIN_DIR/$APP_NAME"
[[ -x "$EXECUTABLE" ]] || die "no executable at $EXECUTABLE after the build."

step "Assembling ${APP#"$ROOT"/}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$EXECUTABLE" "$APP/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST" "$APP/Contents/Info.plist"
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

step "Signing (identity: $SIGN_IDENTITY)"
codesign --force --options runtime \
    --entitlements "$ENTITLEMENTS" \
    -s "$SIGN_IDENTITY" \
    "$APP"
codesign --verify --strict --verbose=2 "$APP"

step "Built ${APP#"$ROOT"/} ($(lipo -archs "$APP/Contents/MacOS/$APP_NAME"))"
