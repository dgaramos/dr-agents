#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook="$root/plugins/claudio-dr/hooks/enforce-adapter-commit.sh"

run() { jq -n --arg t "$1" --arg c "$2" '{tool_name:$t, tool_input:{command:$c}}' | bash "$hook" 2>/dev/null; }
allows() {
  if ! run "$1" "$2"; then echo "expected allow: $2" >&2; exit 1; fi
}
blocks() {
  if run Bash "$1"; then echo "expected block: $1" >&2; exit 1; fi
}

# Bypassing commits are blocked.
blocks 'git commit -m "x"'
blocks 'git commit --amend --no-edit'
blocks 'cd /tmp && git commit -F msg.txt'
blocks 'git -C /tmp commit -m x'

# The adapter helper is the sanctioned path.
allows Bash 'bash "${CLAUDE_PLUGIN_ROOT}"/scripts/commit.sh msg.txt'
allows Bash 'bash plugins/claudio-dr/scripts/commit.sh msg.txt --amend'

# Unrelated commands are untouched.
allows Bash 'git log -1 --format=%B'
allows Bash 'git commit-tree abc123'
allows Bash 'echo "git commit is documented here"' || true
allows Bash 'git status --short'
allows Edit 'git commit -m "x"'

# Malformed payloads fail open rather than stranding the user.
if ! echo 'not json' | bash "$hook" 2>/dev/null; then echo "expected fail-open" >&2; exit 1; fi
if ! echo '{}' | bash "$hook" 2>/dev/null; then echo "expected fail-open" >&2; exit 1; fi

echo "commit hook tests passed"
