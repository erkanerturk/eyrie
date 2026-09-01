#!/usr/bin/env sh

# Validates one commit subject against the Eyrie pattern (see CONTRIBUTING.md).
# Shared by .githooks/commit-msg and CI's commit-lint job so the two can't drift.
# Usage: validate-commit-subject.sh "subject"   (or pipe the subject via stdin)
# Exit codes: 0 valid, 1 wrong shape, 2 Turkish characters (subjects are English-only)

export LC_ALL=en_US.UTF-8

subject="${1:-$(head -n 1)}"

# Alternation, not a bracket class: alternation matches whole byte sequences,
# so it stays correct even if the environment degrades the locale to C
# (a bracket class would decay to single bytes and collide with emoji bytes).
if printf '%s\n' "$subject" | grep -q 'ç\|ğ\|ı\|ö\|ş\|ü\|Ç\|Ğ\|İ\|Ö\|Ş\|Ü'; then
  exit 2
fi

tag_regex='^(✨|🐞|🚨|🔨|🔄|🔀|⏪)? ?\[(feature/Eyrie-[0-9]{1,5}|bugfix/Eyrie-[0-9]{1,5}|hotfix/Eyrie-[0-9]{1,5}|Eyrie-[0-9]{1,5})\]: .+'
word_regex='^(🔨|🔄)? ?(Refactor|Update): .+'
merge_regex='^(🔀 )?Merge (branch|remote-tracking branch|tag|pull request) .+'
revert_regex='^(⏪ )?Revert ".+'
autosquash_regex='^(fixup|squash)! .+'

printf '%s\n' "$subject" | grep -qE "$tag_regex|$word_regex|$merge_regex|$revert_regex|$autosquash_regex"
