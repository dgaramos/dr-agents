#!/usr/bin/env bash
set -euo pipefail

[[ $# -ge 1 ]] || { echo "usage: commit.sh MESSAGE_FILE [git commit options]" >&2; exit 2; }
message_file="$1"
shift
[[ -s "$message_file" ]] || { echo "commit message file must be non-empty" >&2; exit 2; }
readonly trailer='Co-Authored-By: cody-dr[bot] <318732897+cody-dr[bot]@users.noreply.github.com>'
readonly agent_pattern='^co-authored-by:[[:space:]]*(claude|codex|cody-dr|claudio-dr)([^[:alnum:]]|$)'
readonly session_pattern='^claude-session:'
prepared="$(mktemp)"
trap 'rm -f "$prepared"' EXIT
awk -v pattern="$agent_pattern" -v session="$session_pattern" 'tolower($0) !~ pattern && tolower($0) !~ session' "$message_file" >"$prepared"
git interpret-trailers --in-place --trailer "$trailer" "$prepared"
git commit "$@" --file "$prepared"
trailers="$(git log -1 --format=%B | git interpret-trailers --parse)"
[[ "$(printf '%s\n' "$trailers" | grep -Fxc "$trailer")" == 1 ]] || { echo "commit is missing the expected adapter co-author" >&2; exit 1; }
unexpected="$(printf '%s\n' "$trailers" | awk -v pattern="$agent_pattern" -v expected="$trailer" 'tolower($0) ~ pattern && $0 != expected')"
[[ -z "$unexpected" ]] || { echo "commit contains an unexpected agent co-author" >&2; exit 1; }
