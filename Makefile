.PHONY: build test app run release clean

# Linux: KeptCore only. macOS: everything.
build:
	swift build

test:
	swift test

# macOS: dist/Kept.app, ad-hoc signed unless SIGN_IDENTITY is set.
app:
	./scripts/build-app.sh

run: app
	open dist/Kept.app

# macOS: universal dist/Kept-<version>.zip and .dmg plus SHA-256 checksums.
# Signs with SIGN_IDENTITY and notarizes when notary credentials are set
# (docs/RELEASING.md).
release:
	./scripts/package.sh

clean:
	swift package clean
	rm -rf dist
