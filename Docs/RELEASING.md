# Releasing

Releases are built by GitHub Actions (`.github/workflows/release.yml`) on a
`macos-26` runner. Pushing a `v*` tag builds the DMG and publishes a GitHub
Release with it attached.

1. Bump `CFBundleShortVersionString` (and `CFBundleVersion`) in `project.yml`
   — the workflow fails if the version doesn't match the tag.
2. Commit, tag, and push. `Releasing:` is the one non-merge subject allowed
   directly on `main` — the commit-msg hook stamps it 🚀:
   ```bash
   git commit -am "Releasing: v<version>"
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
