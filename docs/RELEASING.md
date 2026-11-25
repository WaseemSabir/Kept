# Releasing Kept

How to version, package, sign, notarize and publish Kept.

## The pieces

| File | Does |
| --- | --- |
| `Resources/Info.plist` | Holds the version (`CFBundleShortVersionString`). |
| `scripts/build-app.sh` (`make app`) | Builds, assembles and signs `dist/Kept.app`; stamps the version and build number. |
| `scripts/package.sh` (`make release`) | Builds a universal app, signs it, notarizes and staples it when it can, then makes the disk image. |
| `.github/workflows/release.yml` | Runs `package.sh` and publishes a GitHub release with the disk image, when you run it by hand or push a tag. |

## Versioning

- **The version lives in `Resources/Info.plist`** (`CFBundleShortVersionString`,
  `MAJOR.MINOR.PATCH`), and only there: the app reads it from its bundle
  (Settings › About), the release workflow tags and names the release after
  it, and it refuses a tag that doesn't match it or a version that's already
  released.
- `build-app.sh` stamps the copy inside the bundle, never the source file:
  - `CFBundleShortVersionString`: `VERSION` if set (for example `0.2.0-dev` for a
    local test build), otherwise the value in `Info.plist`.
  - `CFBundleVersion`: `BUILD_NUMBER` if set, otherwise `git rev-list --count HEAD`.
    It only grows on `master`, and it's what macOS and Sparkle compare between
    builds. A shallow clone undercounts, so the release workflow fetches the
    full history. The `1` in the source `Info.plist` is a placeholder.
- `package.sh` names the disk image after the stamped version
  (`Kept-<version>.dmg`).

## Cut a release

1. **Bump the version** on `master`:

   ```sh
   plutil -replace CFBundleShortVersionString -string 0.2.0 Resources/Info.plist
   git commit -am "Bump the version to 0.2.0"
   git push origin master
   ```

   Wait for CI to pass on that commit.
2. **Run the release:** Actions › Release › Run workflow, on `master`. It tags
   that commit `v0.2.0` and releases it. Pushing the tag yourself does the
   same:

   ```sh
   git tag -a v0.2.0 -m "Kept 0.2.0"
   git push origin v0.2.0
   ```

3. **The Release workflow** builds a universal app on the newest stable Xcode,
   signs it, notarizes it if it can, and verifies the disk image before
   anything is published: its checksum, the `Applications` link,
   `lipo -archs` (arm64 and x86_64), `codesign --verify --deep --strict` on the
   app inside, and a short launch of each architecture (x86_64 under
   Rosetta). The run's summary lists the architectures, the signature, whether
   it's notarized, and the SHA-256.
4. **The release is published** as the latest, with one file,
   `Kept-<version>.dmg`, and notes that cover installing, the first launch of an
   unnotarized build, the SHA-256 and the changes since the last release.
   GitHub adds the source code archives itself.

The workflow stops before building if the version is already released, or if
its tag already marks a different commit, so bump the version first. If a run
fails, fix the cause and run it again: nothing is published until the disk
image passes its checks.

**Locally** (macOS): `make release` makes an ad-hoc signed package in `dist/`.

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_KEYCHAIN_PROFILE=kept make release
```

signs and notarizes with your own certificate and a notary profile saved by
`xcrun notarytool store-credentials kept --key AuthKey_XXXX.p8 --key-id … --issuer …`.

## What gets made

`dist/Kept-<version>.dmg`: `Kept.app` and an `Applications` link, compressed
(UDZO). Signed and notarized like the app when the secrets allow it. Its
SHA-256 is in the release notes; check a download with
`shasum -a 256 Kept-<version>.dmg`.

## Signing and notarization secrets

The workflow degrades gracefully, depending on which repository secrets exist
(Settings › Secrets and variables › Actions):

| Secrets | Result |
| --- | --- |
| none | Ad-hoc signature (`codesign -s -`), hardened runtime, sandbox entitlements. Not notarized. |
| `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD` | Developer ID signature with a secure timestamp, on the app and the disk image. Not notarized. |
| both of the above and `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_P8` | Signed, notarized and stapled (the app, then the disk image). |

How to get them (needs the Apple Developer Program):

- **`MACOS_CERTIFICATE_P12`**: create a *Developer ID Application* certificate
  (Xcode › Settings › Accounts › Manage Certificates › +), export it with its
  private key from Keychain Access as a `.p12` with a password, and store it
  base64-encoded: `base64 -i DeveloperID.p12 | pbcopy`.
- **`MACOS_CERTIFICATE_PASSWORD`**: that export password.
- **`NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_P8`**: in App Store Connect ›
  Users and Access › Integrations › App Store Connect API, create a team key
  (the Developer role can notarize). Download `AuthKey_<id>.p8` (only possible
  once) and paste its contents (or their base64) as `NOTARY_KEY_P8`; the key ID
  and issuer ID are on the same page.

The workflow imports the certificate into a temporary keychain, signs with the
first *Developer ID Application* identity in it, and deletes the keychain at the
end of the job, even if the job fails. It never prints the secrets. If only some
notary secrets exist, it warns and skips notarization.

Signing is inside out: nested code first (none yet; Sparkle would add a framework
and XPC services), then the app, never with `--deep`. Notarization uses
`xcrun notarytool submit --wait`, prints Apple's log if a submission is rejected,
and staples with retries.

## Gatekeeper and unnotarized builds

Browsers quarantine downloads, and Gatekeeper blocks a quarantined app that isn't
notarized: "“Kept” Not Opened. Apple could not verify “Kept” is free of
malware…", with **Done** and **Move to Trash**.

- **macOS 15 and later:** click **Done**, then click **Open Anyway** in System
  Settings › Privacy & Security (under Security) and confirm with an
  administrator password or Touch ID. The Control-click › Open bypass no
  longer exists.
- **macOS 14:** Control-click Kept in Applications and choose **Open**.
- **Any version:** `xattr -dr com.apple.quarantine /Applications/Kept.app` in
  Terminal removes the quarantine, and Kept opens normally.

The release notes of an unnotarized build carry these steps.

Notarized releases open normally.

## Accessibility access and the ad-hoc trap

Kept pastes by posting ⌘V, which needs Accessibility access. macOS ties that grant
to the app's *designated requirement*:

- **Developer ID:** the requirement names the bundle ID and team, so the grant
  survives updates.
- **Ad-hoc:** the requirement is the build's code hash (cdhash), so every new
  build, whether an update or a local rebuild, silently loses the grant. System
  Settings still shows the switch on. Users of ad-hoc releases have to remove
  Kept from System Settings › Privacy & Security › Accessibility and add it
  again after each update, or run `tccutil reset Accessibility app.kept.Kept`.

That's the main reason to sign releases with Developer ID.

### Local builds: use one persistent self-signed identity

1. In Keychain Access, choose Keychain Access › Certificate Assistant ›
   Create a Certificate…
2. Name it `Kept Local Signing`, set Identity Type to *Self Signed Root* and
   Certificate Type to *Code Signing*, and create it.
3. Build with it, for example from your shell profile:

   ```sh
   export SIGN_IDENTITY="Kept Local Signing"
   make run
   ```

The requirement is now the bundle ID and that certificate, the same for every
build, so the grant sticks. Reset once after switching
(`tccutil reset Accessibility app.kept.Kept`). If `codesign` asks to use the key,
choose Always Allow. If it says the identity isn't valid, open the certificate
in Keychain Access and set Trust › Code Signing to Always Trust.

## Homebrew cask (later)

- **homebrew/cask** only takes apps that pass Gatekeeper: Homebrew 5 deprecated
  casks that fail it and removed them on 2026-09-01, and `--no-quarantine` is
  deprecated. So Kept needs Developer ID signing and notarization first, a
  public repository, and enough users to meet the tap's notability rules.
- Until then, a **personal tap** works: a public repository
  `WaseemSabir/homebrew-tap` with `Casks/kept.rb`. Users run
  `brew install --cask WaseemSabir/tap/kept`; an unnotarized build still meets
  Gatekeeper on first launch.

```ruby
cask "kept" do
  version "0.2.0"
  sha256 "…" # from the release notes

  url "https://github.com/WaseemSabir/Kept/releases/download/v#{version}/Kept-#{version}.dmg"
  name "Kept"
  desc "Keyboard-first clipboard history"
  homepage "https://github.com/WaseemSabir/Kept"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Kept.app"

  uninstall quit: "app.kept.Kept"

  zap trash: [
    "~/Library/Application Scripts/app.kept.Kept",
    "~/Library/Containers/app.kept.Kept",
  ]
end
```

For each release, update `version` and `sha256` (in the official tap,
`brew bump-cask-pr kept --version 0.2.1` does this), then check the cask with
`brew audit --cask --strict WaseemSabir/tap/kept`.
