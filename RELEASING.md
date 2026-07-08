# Releasing

1. Bump `CFBundleShortVersionString` (and `CFBundleVersion`) in `project.yml`.
2. Build the DMG:
   ```bash
   ./Scripts/make-dmg.sh
   ```
3. Commit, tag, and publish:
   ```bash
   git commit -am "Release v<version>"
   git tag v<version>
   git push && git push --tags
   gh release create v<version> dist/Eyrie-<version>.dmg \
     --title "Eyrie v<version>" --generate-notes
   ```

The app is ad-hoc signed (no notarization), so first launch on another Mac
requires right-click → Open, or:

```bash
xattr -dr com.apple.quarantine /Applications/Eyrie.app
```
