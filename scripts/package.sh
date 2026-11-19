#!/usr/bin/env bash
# Builds a universal, signed Kept.app (scripts/build-app.sh), notarizes and
# staples it when notary credentials are set, and packages it for release:
#
#   dist/Kept-<version>.zip      the app, zipped with ditto
#   dist/Kept-<version>.dmg      the app and an Applications link
#   dist/Kept-<version>.sha256   SHA-256 checksums of both
#
# Environment (see docs/RELEASING.md):
#   SIGN_IDENTITY=…            codesign identity (default: "-", an ad-hoc signature);
#                              notarization needs "Developer ID Application: …"
#   VERSION=…, BUILD_NUMBER=…  passed to build-app.sh (default: Info.plist, commit count)
#   UNIVERSAL=0                build only for this Mac's architecture (default: 1)
#   Notarization, optional; set one of:
#     NOTARY_KEYCHAIN_PROFILE=…  a profile saved with `xcrun notarytool store-credentials`
#     NOTARY_KEY_ID=…, NOTARY_ISSUER_ID=… and NOTARY_KEY_PATH=… (an AuthKey_….p8 file)
#                                or NOTARY_KEY_P8=… (the key itself, PEM or base64)
#   NOTARIZE=0                 skip notarization even if credentials are set
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Kept"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
export SIGN_IDENTITY="${SIGN_IDENTITY:--}"
export UNIVERSAL="${UNIVERSAL:-1}"

step() { printf '==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
indent() { sed 's/^/    /'; }
plist_value() { /usr/libexec/PlistBuddy -c "Print :$1" "$2"; }
# json_value KEY <<< JSON: a top-level string from notarytool's JSON output.
json_value() {
    local json
    json="$(cat)"
    plutil -extract "$1" raw -o - - <<<"$json" 2>/dev/null ||
        sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" <<<"$json"
}

[[ "$(uname -s)" == "Darwin" ]] || die "Kept can only be packaged on macOS."
for tool in codesign ditto hdiutil lipo shasum xcrun; do
    command -v "$tool" >/dev/null || die "$tool not found. Install the Xcode command line tools."
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/kept-package.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Notarization: decide up front, so a missing credential fails before the build.
NOTARIZING=0
notary_args=()
notary_how=""
if [[ "${NOTARIZE:-1}" != "0" ]]; then
    if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
        NOTARIZING=1
        notary_args=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
        notary_how="keychain profile"
    elif [[ -n "${NOTARY_KEY_ID:-}${NOTARY_ISSUER_ID:-}${NOTARY_KEY_PATH:-}${NOTARY_KEY_P8:-}" ]]; then
        missing=""
        [[ -n "${NOTARY_KEY_ID:-}" ]] || missing="$missing NOTARY_KEY_ID"
        [[ -n "${NOTARY_ISSUER_ID:-}" ]] || missing="$missing NOTARY_ISSUER_ID"
        [[ -n "${NOTARY_KEY_PATH:-}${NOTARY_KEY_P8:-}" ]] || missing="$missing NOTARY_KEY_PATH|NOTARY_KEY_P8"
        [[ -z "$missing" ]] || die "notarization also needs:$missing (or set NOTARIZE=0)."
        key_path="${NOTARY_KEY_PATH:-$WORK/notary-key.p8}"
        if [[ -z "${NOTARY_KEY_PATH:-}" ]]; then
            if [[ "$NOTARY_KEY_P8" == *"BEGIN PRIVATE KEY"* ]]; then
                (umask 077 && printf '%s\n' "$NOTARY_KEY_P8" >"$key_path")
            else
                (umask 077 && printf '%s' "$NOTARY_KEY_P8" | base64 --decode >"$key_path") ||
                    die "NOTARY_KEY_P8 is neither a .p8 key nor base64 of one."
            fi
        fi
        grep -q "BEGIN PRIVATE KEY" "$key_path" 2>/dev/null ||
            die "the notary key isn't a .p8 private key (NOTARY_KEY_PATH or NOTARY_KEY_P8)."
        NOTARIZING=1
        notary_args=(--key "$key_path" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
        notary_how="App Store Connect API key"
    fi
fi
if ((NOTARIZING)) && [[ "$SIGN_IDENTITY" == "-" ]]; then
    die "notarization needs a Developer ID signature: set SIGN_IDENTITY (or NOTARIZE=0)."
fi
# Real identities get a secure timestamp; notarization requires one.
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    export SIGN_TIMESTAMP=1
fi

if [[ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]]; then
    note "warning: the working tree has uncommitted changes"
fi

# notarize FILE: submits FILE, waits, and fails unless Apple accepts it.
notarize() {
    local file="$1" output id status
    step "Notarizing $(basename "$file") ($notary_how; this can take a few minutes)"
    output="$(xcrun notarytool submit "$file" "${notary_args[@]}" \
        --wait --output-format json)" ||
        die "notarytool could not submit $(basename "$file")."
    id="$(json_value id <<<"$output")"
    status="$(json_value status <<<"$output")"
    note "submission $id: $status"
    if [[ "$status" != "Accepted" ]]; then
        [[ -z "$id" ]] || xcrun notarytool log "$id" "${notary_args[@]}" >&2 || true
        die "Apple did not accept $(basename "$file") (${status:-no status})."
    fi
}

# staple TARGET: attaches the notarization ticket (retried: tickets take a moment to appear).
staple() {
    local target="$1" attempt
    for attempt in 1 2 3; do
        if xcrun stapler staple "$target"; then
            xcrun stapler validate "$target"
            return 0
        fi
        note "stapling failed (attempt $attempt of 3)"
        ((attempt == 3)) || sleep 20
    done
    die "could not staple the ticket to $(basename "$target")."
}

step "Packaging $APP_NAME (identity: $SIGN_IDENTITY; notarize: $([[ $NOTARIZING == 1 ]] && echo yes || echo no))"
"$ROOT/scripts/build-app.sh"

VERSION="$(plist_value CFBundleShortVersionString "$APP/Contents/Info.plist")"
BUILD_NUMBER="$(plist_value CFBundleVersion "$APP/Contents/Info.plist")"
ZIP="$DIST/$APP_NAME-$VERSION.zip"
DMG="$DIST/$APP_NAME-$VERSION.dmg"
SUMS="$DIST/$APP_NAME-$VERSION.sha256"

step "Verifying ${APP#"$ROOT"/}"
note "version: $VERSION ($BUILD_NUMBER)"
note "architectures: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | indent
codesign --display --verbose=2 "$APP" 2>&1 | indent
note "entitlements:"
codesign --display --entitlements - "$APP" 2>/dev/null | indent

if ((NOTARIZING)); then
    ditto -c -k --keepParent "$APP" "$WORK/$APP_NAME-notarize.zip"
    notarize "$WORK/$APP_NAME-notarize.zip"
    staple "$APP"
fi

step "Zipping ${ZIP#"$ROOT"/}"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

step "Making ${DMG#"$ROOT"/}"
staging="$WORK/dmg"
mkdir -p "$staging"
ditto "$APP" "$staging/$APP_NAME.app"
ln -s /Applications "$staging/Applications"
rm -f "$DMG"
# hdiutil sometimes reports "Resource busy" on busy machines (CI); retry.
for attempt in 1 2 3 4 5; do
    if hdiutil create -volname "$APP_NAME" -srcfolder "$staging" -fs HFS+ \
        -format UDZO -imagekey zlib-level=9 -ov "$DMG"; then
        break
    fi
    ((attempt < 5)) || die "hdiutil could not create the disk image."
    note "hdiutil create failed (attempt $attempt of 5); retrying"
    sleep $((attempt * 5))
done
hdiutil verify "$DMG" 2>&1 | tail -n 1 | indent
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --timestamp -s "$SIGN_IDENTITY" "$DMG"
    codesign --verify --strict --verbose=2 "$DMG" 2>&1 | indent
fi
if ((NOTARIZING)); then
    notarize "$DMG"
    staple "$DMG"
fi

step "Checksums (${SUMS#"$ROOT"/})"
(cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" >"$(basename "$SUMS")")
indent <"$SUMS"

step "Gatekeeper"
if spctl --assess --type execute --verbose=2 "$APP" 2>&1 | indent; then
    :
elif ((NOTARIZING)); then
    die "Gatekeeper rejects the notarized app."
else
    note "(expected without notarization: users approve Kept under Privacy & Security)"
fi

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    signature="ad-hoc"
else
    details="$(codesign --display --verbose=2 "$APP" 2>&1)"
    signature="$(sed -n 's/^Authority=//p' <<<"$details" | sed -n 1p)"
fi
step "Packaged $APP_NAME $VERSION ($BUILD_NUMBER)"
note "signature: ${signature:-$SIGN_IDENTITY}; notarized: $([[ $NOTARIZING == 1 ]] && echo yes || echo no)"
for file in "$ZIP" "$DMG" "$SUMS"; do
    note "${file#"$ROOT"/} ($(du -h "$file" | cut -f1 | tr -d ' '))"
done

# Hand the results to GitHub Actions when running there.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
        echo "version=$VERSION"
        echo "build=$BUILD_NUMBER"
        echo "zip=$ZIP"
        echo "dmg=$DMG"
        echo "checksums=$SUMS"
        echo "signature=${signature:-$SIGN_IDENTITY}"
        echo "notarized=$([[ $NOTARIZING == 1 ]] && echo true || echo false)"
    } >>"$GITHUB_OUTPUT"
fi
