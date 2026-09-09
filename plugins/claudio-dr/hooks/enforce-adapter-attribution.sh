#!/usr/bin/env bash
# Keep Claudio DR attribution intact for commits and GitHub publication.
#
# Both rules already exist: the commit helper is mandated by the implement-issue
# and handle-pr-findings skills, and App-first routing by the publication
# routing contract. Neither reaches a session that loads no skill, which then
# falls back to a plain `git commit` or a personal `gh` call. This hook applies
# both regardless of how the command was reached.
#
# Fails open: anything this hook cannot parse is allowed through. A hook that
# blocks on its own errors would strand the user with no way to work.
set -uo pipefail

payload="$(cat)" || exit 0
command -v jq >/dev/null 2>&1 || exit 0

tool="$(jq -r '.tool_name // empty' <<<"$payload" 2>/dev/null)" || exit 0
[[ "$tool" == "Bash" ]] || exit 0
cmd="$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null)" || exit 0
[[ -n "$cmd" ]] || exit 0

# Escape hatch for the evidence-based personal fallback the routing contract
# allows. It is deliberately explicit: the operator states the intent in the
# command itself, so the fallback stays visible in the transcript.
grep -q 'DR_PERSONAL_FALLBACK=1' <<<"$cmd" && exit 0

block() {
  printf '%s\n' "$1" >&2
  exit 2
}

# --- Commit attribution ----------------------------------------------------
# Matches `git commit`, including global options that take a value such as
# `git -C <dir> commit`. Leaves `git log`, `git commit-tree`, and unrelated
# commands that merely contain the word alone.
git_commit_re='(^|[;&|(]|[[:space:]])git[[:space:]]+(-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?[[:space:]]+)*commit([[:space:]]|$)'
if grep -qE "$git_commit_re" <<<"$cmd"; then
  # The helper runs `git commit` internally, but that is a nested process and
  # never reaches this hook. Reaching here via the helper means it was invoked
  # directly, which is the sanctioned path.
  grep -q 'commit\.sh' <<<"$cmd" || block 'Blocked: this commit would bypass the Claudio DR commit helper.

Adapter commits must carry the claudio-dr[bot] co-author trailer. Write the
message to a file and commit through the helper, which strips generic model
attribution, preserves human co-authors, and verifies the result:

  bash "${CLAUDE_PLUGIN_ROOT}"/scripts/commit.sh <message-file> [git commit options]

The helper passes through git commit options, so --amend and --allow-empty work
as usual. It does not change the Git author or signing configuration.'
fi

# --- Publication routing ---------------------------------------------------
# Mutating gh commands publish under the personal account. The App publisher is
# dispatched with `gh workflow run`, which stays allowed.
gh_write_re='(^|[;&|(]|[[:space:]])gh[[:space:]]+(pr[[:space:]]+(create|review|comment|edit|merge|close|reopen)|issue[[:space:]]+(create|comment|edit|close|reopen))([[:space:]]|$)'
gh_api_write_re='(^|[;&|(]|[[:space:]])gh[[:space:]]+api([[:space:]]|$).*(-X|--method)[[:space:]]+(POST|PATCH|PUT|DELETE)'
if grep -qE "$gh_write_re" <<<"$cmd" || grep -qEi "$gh_api_write_re" <<<"$cmd"; then
  block 'Blocked: this would publish to GitHub as the personal account.

Claudio DR publication is App-first. Check the route first, then dispatch the
publisher workflow so the result is authored by claudio-dr[bot]:

  bash <catalog>/core/pr-review/scripts/select-publisher.sh OWNER/REPO WORKFLOW
  gh workflow run <publisher-workflow> -f ...

See core/pr-review/references/publication-routing-contract.md. A personal
fallback needs evidence that the App operation is unavailable — a missing
profile or a generic error is not evidence. When that evidence exists, state it
and prefix the command with DR_PERSONAL_FALLBACK=1 so the fallback is explicit
and visible in the transcript.'
fi

exit 0
