#!/usr/bin/env sh

# Table-driven tests for .githooks/commit-msg: verdict + resulting first line.
# A rejected message must leave the file untouched (no emoji persisted).
# Run locally or in CI:  sh Scripts/test-hooks.sh

root="$(git rev-parse --show-toplevel)" || exit 1
cd "$root" || exit 1

tmp="$(mktemp)"
trap 'rm -f "$tmp" "$tmp.tmp"' EXIT
pass=0
fail=0

# The main-branch guard keys off the current branch; pin a feature branch so
# the table behaves the same on any checkout (incl. CI's detached HEAD), and
# override per-case to exercise the guard itself.
EYRIE_TEST_BRANCH="feature/Eyrie-0"
export EYRIE_TEST_BRANCH

# check <ok|reject> <subject> [expected first line after the hook; defaults to unchanged]
check() {
  printf '%s\n' "$2" > "$tmp"
  if sh .githooks/commit-msg "$tmp" >/dev/null 2>&1; then got=ok; else got=reject; fi
  first="$(head -n 1 "$tmp")"
  want_line="${3:-$2}"
  if [ "$got" = "$1" ] && [ "$first" = "$want_line" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: want=$1 subject='$2' -> got=$got line='$first'"
  fi
}

# Happy path: every pattern gets its emoji exactly once
check ok '[feature/Eyrie-3]: add thing'            '✨ [feature/Eyrie-3]: add thing'
check ok '[bugfix/Eyrie-4]: fix thing'             '🐞 [bugfix/Eyrie-4]: fix thing'
check ok '[hotfix/Eyrie-5]: urgent thing'          '🚨 [hotfix/Eyrie-5]: urgent thing'
check ok '[Eyrie-9]: misc chore'                   '✨ [Eyrie-9]: misc chore'
check ok 'Refactor: split parser'                  '🔨 Refactor: split parser'
check ok 'Update: bump docs'                       '🔄 Update: bump docs'
check ok 'Releasing: v0.6.0'                       '🚀 Releasing: v0.6.0'
check ok '✨ [feature/Eyrie-3]: already prefixed'  '✨ [feature/Eyrie-3]: already prefixed'

# git-generated subjects
check ok "Merge branch 'main' into feature/Eyrie-3" "🔀 Merge branch 'main' into feature/Eyrie-3"
check ok 'Merge pull request #7 from Hkaysili/feature/Eyrie-3' '🔀 Merge pull request #7 from Hkaysili/feature/Eyrie-3'
check ok 'Revert "✨ [feature/Eyrie-3]: add thing"' '⏪ Revert "✨ [feature/Eyrie-3]: add thing"'
check ok 'fixup! [feature/Eyrie-3]: add thing'
check ok 'squash! ✨ [feature/Eyrie-3]: add thing'

# Case matters — none of these may slip through unprefixed
check reject '[eyrie-3]: lowercase tag'
check reject '[FEATURE/EYRIE-3]: shouting'
check reject 'refactor: lowercase variant'

# Merge is not a blanket bypass
check reject 'Merge the two parsers into one function'

# Shape violations
check reject 'bad message with no pattern'
check reject '[feature/Eyrie-]: missing number'
check reject 'releasing: lowercase variant'

# main takes no direct work: releases and merges only
EYRIE_TEST_BRANCH="main"
check reject '[feature/Eyrie-9]: work committed on main'
check reject 'Update: docs edited on main'
check ok 'Releasing: v9.9.9'                        '🚀 Releasing: v9.9.9'
check ok "Merge branch 'main' of github.com:erkanerturk/eyrie" "🔀 Merge branch 'main' of github.com:erkanerturk/eyrie"
EYRIE_TEST_BRANCH="feature/Eyrie-0"

# English-only subjects
check reject '[feature/Eyrie-3]: turkce karakter denemesi gibi ama gercekten şöyle'
check reject 'Update: dokumantasyonu güncelle'

# The emoji must not false-positive as Turkish bytes, even under LC_ALL=C
printf '%s\n' '[feature/Eyrie-3]: pure english subject' > "$tmp"
if LC_ALL=C sh .githooks/commit-msg "$tmp" >/dev/null 2>&1 \
   && [ "$(head -n 1 "$tmp")" = '✨ [feature/Eyrie-3]: pure english subject' ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1))
  echo "FAIL: LC_ALL=C false positive -> $(head -n 1 "$tmp")"
fi

echo "hook tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
