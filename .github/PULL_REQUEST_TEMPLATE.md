## Summary

<!-- What changed and why? Link any related issues (e.g., Fixes #12). -->

## Testing

- [ ] `swift test` passes
- [ ] `make app` builds and runs cleanly on macOS (if app code changed)
- [ ] Reviewed UI changes against `docs/DESIGN.md` (light/dark, keyboard navigation, VoiceOver)

## Checklist

- [ ] Non-AppKit logic stays in `KeptCore` (Foundation-only, Linux-compatible)
- [ ] No new third-party dependencies added without discussion
- [ ] Updated `docs/ROADMAP.md` or other docs if behavior changed
