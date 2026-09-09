#!/usr/bin/env bash
# Block `git commit` that bypasses the adapter commit helper.
#
# Claudio DR commits must carry the adapter's co-author trailer. The skills say
# so, but a session that never loads a skill never receives that instruction.
# This hook enforces it regardless of how the commit was reached.
#
# Fails open: anything this hook cannot parse is allowed through. A hook that
# blocks on its own errors would strand the user with no way to commit.
set -uo pipefail

payload="$(cat)" || exit 0
command -v jq >/dev/null 2>&1 || exit 0

tool="$(jq -r '.tool_name // empty' <<<"$payload" 2>/dev/null)" || exit 0
[[ "$tool" == "Bash" ]] || exit 0
cmd="$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null)" || exit 0
[[ -n "$cmd" ]] || exit 0

# Only `git commit` is in scope; `git log`, `git commit-tree`, and unrelated
# commands that merely contain the word are not.
git_commit_re='(^|[;&|(]|[[:space:]])git[[:space:]]+(-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?[[:space:]]+)*commit([[:space:]]|$)'
grep -qE "$git_commit_re" <<<"$cmd" || exit 0

# The helper itself runs `git commit` internally, but that is a nested process
# and never reaches this hook. Reaching here via the helper means the user
# invoked it directly, which is exactly what we want.
grep -q 'commit\.sh' <<<"$cmd" && exit 0

cat >&2 <<'MSG'
Blocked: this commit would bypass the Claudio DR commit helper.

Adapter commits must carry the claudio-dr[bot] co-author trailer. Write the
message to a file and commit through the helper, which strips generic model
attribution, preserves human co-authors, and verifies the result:

  bash "${CLAUDE_PLUGIN_ROOT}"/scripts/commit.sh <message-file> [git commit options]

The helper passes through git commit options, so --amend and --allow-empty work
as usual. It does not change the Git author or signing configuration.
MSG
exit 2
