#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook="$root/plugins/claudio-dr/hooks/enforce-adapter-attribution.sh"

run() { jq -n --arg t "$1" --arg c "$2" '{tool_name:$t, tool_input:{command:$c}}' | bash "$hook" 2>/dev/null; }
allows() { run "$1" "$2" || { echo "expected allow: $2" >&2; exit 1; }; }
blocks() { run Bash "$1" && { echo "expected block: $1" >&2; exit 1; } || true; }

# --- commit attribution ---
blocks 'git commit -m "x"'
blocks 'git commit --amend --no-edit'
blocks 'cd /tmp && git commit -F msg.txt'
blocks 'git -C /tmp commit -m x'
allows Bash 'bash "${CLAUDE_PLUGIN_ROOT}"/scripts/commit.sh msg.txt'
allows Bash 'bash plugins/claudio-dr/scripts/commit.sh msg.txt --amend'
allows Bash 'git log -1 --format=%B'
allows Bash 'git commit-tree abc123'
allows Bash 'git status --short'

# --- publication routing ---
blocks 'gh pr create --base main --title x --body y'
blocks 'gh pr review 12 --comment -b hi'
blocks 'gh pr comment 12 -b hi'
blocks 'gh issue create -t x -b y'
blocks 'gh pr merge 12 --squash'
blocks 'gh api -X POST repos/o/r/issues -f title=x'
blocks 'gh api --method PATCH repos/o/r/pulls/1'

# The App publisher and read-only queries stay available.
allows Bash 'gh workflow run publish-claudio-pr.yml -f title=x -f body=y'
allows Bash 'gh pr view 257 --json author'
allows Bash 'gh api repos/o/r/pulls/1 --jq .title'
allows Bash 'gh pr list --state open'

# --- evidence-based personal fallback ---
allows Bash 'DR_PERSONAL_FALLBACK=1 gh pr create --base main --title x --body y'

# --- other tools are untouched ---
allows Edit 'git commit -m "x"'

# --- fails open ---
echo 'not json' | bash "$hook" 2>/dev/null || { echo "expected fail-open" >&2; exit 1; }
echo '{}' | bash "$hook" 2>/dev/null || { echo "expected fail-open" >&2; exit 1; }

echo "attribution hook tests passed"
