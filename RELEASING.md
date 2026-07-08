# Releasing

Releases are built by GitHub Actions (`.github/workflows/release.yml`) on a
`macos-26` runner. Pushing a `v*` tag builds the DMG and publishes a GitHub
Release with it attached.

1. Bump `CFBundleShortVersionString` (and `CFBundleVersion`) in `project.yml`
   — the workflow fails if the version doesn't match the tag.
2. Commit, tag, and push:
   ```bash
   git commit -am "Release v<version>"
   git tag v<version>
   git push && git push --tags
   ```
3. Watch the run and find the DMG on the release page:
   ```bash
   gh run watch
   gh release view v<version> --web
   ```

To build the DMG locally instead: `./Scripts/make-dmg.sh` → `dist/Eyrie-<version>.dmg`.

The app is ad-hoc signed (no notarization), so first launch on another Mac
requires right-click → Open, or:

```bash
xattr -dr com.apple.quarantine /Applications/Eyrie.app
```
