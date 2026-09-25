#!/usr/bin/env sh

# CI-only: installs a pinned, checksum-verified XcodeGen instead of whatever
# `brew install xcodegen` resolves to on the day — its output is the Xcode
# project that builds the shipped binary. Bump version and sha256 together:
#   curl -sSLo x.zip https://github.com/yonaskolb/XcodeGen/releases/download/<v>/xcodegen.zip && shasum -a 256 x.zip

set -eu

version=2.46.0
sha256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806

dest="${RUNNER_TEMP:-$(mktemp -d)}/xcodegen-$version"
curl -fsSL -o "$dest.zip" "https://github.com/yonaskolb/XcodeGen/releases/download/$version/xcodegen.zip"
echo "$sha256  $dest.zip" | shasum -a 256 -c - >&2
unzip -q -o "$dest.zip" -d "$dest"

# The binary finds its presets via ../share, so it runs from the unpacked tree.
bin="$dest/xcodegen/bin"
if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$bin" >> "$GITHUB_PATH"
else
  echo "$bin"
fi
