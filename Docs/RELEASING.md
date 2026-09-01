# Releasing

Releases are built by GitHub Actions (`.github/workflows/release.yml`) on a
`macos-26` runner. Pushing a `v*` tag builds the DMG and publishes a GitHub
Release with it attached.

`main` is protected by a ruleset (changes only via PR, `build-and-test`
required), so the version bump lands through a release PR:

1. Branch off `main` as `release/v<version>`. Bump
   `CFBundleShortVersionString` (and `CFBundleVersion`) in `project.yml`, run
   `xcodegen generate` (it syncs `App/Info.plist`) — the workflow fails if the
   version doesn't match the tag. Commit as `Releasing: v<version>` (the
   commit-msg hook stamps it 🚀).
2. Push the branch, open a PR titled `🚀 Releasing: v<version>`, and wait for
   green CI **and at least one approving review**, then merge.
3. Tag the merge commit on `main` and push the tag — that push triggers the
   release build:
   ```bash
   git checkout main && git pull
   git tag v<version>
   git push --tags
   ```
4. Watch the run and find the DMG on the release page:
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
