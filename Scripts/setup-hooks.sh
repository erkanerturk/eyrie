#!/usr/bin/env sh

# One-shot bootstrap for the versioned git hooks in .githooks/.
# Eyrie has no npm toolchain, so instead of husky the hooks are plain sh
# wired in via core.hooksPath. Run once after cloning:
#
#   ./Scripts/setup-hooks.sh

root="$(git rev-parse --show-toplevel)" || exit 1
cd "$root" || exit 1

# Zip/tarball downloads lose the executable bit git preserves, so restore it.
chmod +x .githooks/* Scripts/*.sh
git config core.hooksPath .githooks

echo "✅ git hooks installed (core.hooksPath -> .githooks)"
