.PHONY: build test app run clean

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

clean:
	swift package clean
	rm -rf dist
