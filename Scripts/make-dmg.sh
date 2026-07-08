#!/bin/bash
# Builds a Release Eyrie.app and packages it into dist/Eyrie-<version>.dmg
# with an /Applications symlink for drag-and-drop install.
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app}"

if ! command -v xcodegen >/dev/null; then
    echo "xcodegen is required: brew install xcodegen" >&2
    exit 1
fi

xcodegen generate
xcodebuild -project Eyrie.xcodeproj -scheme Eyrie -configuration Release \
    -derivedDataPath build build

APP="build/Build/Products/Release/Eyrie.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="dist/Eyrie-$VERSION.dmg"

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

mkdir -p dist
rm -f "$DMG"
hdiutil create -volname "Eyrie" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

echo "Created $DMG"
