#!/usr/bin/env bash
# Validate a review publication manifest before it is dispatched.
#
# The server-side publisher already rejects a malformed manifest, but it does so
# one failure at a time and only after a workflow run. This script is the local
# replica of those checks plus the one the publisher cannot make cheaply --
# whether an inline finding's line is actually in the diff -- and it reports
# EVERY failure in a single execution, so an invalid manifest costs one local
# run rather than four round trips.
#
# It is read-only by construction: it issues no mutating API call and never
# dispatches. The manifest shape it enforces is documented as a fenced example
# in review-contract.md; this script is its executable definition.
#
# NOTE: the review-thread paging query below is duplicated in
# load-review-threads.sh and verify-review-publication.sh, which the issues
# declare independent of one another. dr-agents#322 owns consolidating the three
# query sites into one.
set -euo pipefail

[[ $# == 1 ]] || { echo "usage: validate-review-manifest.sh MANIFEST_PATH" >&2; exit 2; }
readonly manifest="$1"
[[ -r "$manifest" ]] || { echo "not readable: $manifest" >&2; exit 2; }
jq -e . "$manifest" >/dev/null 2>&1 || { echo "not valid JSON: $manifest" >&2; exit 2; }

failures=0
problem() { echo "manifest: $1" >&2; failures=$((failures + 1)); }

field() { jq -r "$1 // empty" "$manifest"; }
readonly repository="$(field .repository)"
readonly pr_number="$(field .pr_number)"
readonly event="$(field .event)"
readonly reviewed_head_sha="$(field .reviewed_head_sha)"

[[ -n "$repository" && "$repository" == */* ]] \
  || { echo "manifest: repository must be OWNER/REPO" >&2; exit 2; }
[[ "$pr_number" =~ ^[1-9][0-9]*$ ]] \
  || { echo "manifest: pr_number must be a positive integer" >&2; exit 2; }

readonly owner="${repository%%/*}"
readonly name="${repository##*/}"

inline_comments="$(jq -c '.inline_comments // []' "$manifest")"
replies="$(jq -c '.replies // []' "$manifest")"
resolve_thread_ids="$(jq -c '.resolve_thread_ids // []' "$manifest")"

# --- shape ---------------------------------------------------------------
# The same three predicates the publisher applies, so a manifest that passes
# here cannot be rejected by the server for its shape.
jq -e 'type == "array" and all(.[]; type == "object"
  and (.path | type == "string" and length > 0)
  and (.line | type == "number" and floor == . and . > 0)
  and (.body | type == "string" and length > 0))' <<<"$inline_comments" >/dev/null \
  || problem "invalid inline_comments: each entry needs path, a positive integer line, and a non-empty body"
jq -e 'type == "array" and all(.[]; type == "object"
  and (.comment_id | type == "number" and floor == . and . > 0)
  and (.body | type == "string" and length > 0))' <<<"$replies" >/dev/null \
  || problem "invalid replies: each entry needs a positive integer comment_id and a non-empty body"
jq -e 'type == "array" and all(.[]; type == "string" and length > 0)' \
  <<<"$resolve_thread_ids" >/dev/null \
  || problem "invalid resolve_thread_ids: expected an array of non-empty strings"

# An agent review is always a COMMENT: it may identify a blocking risk but the
# merge decision stays human, so APPROVE and REQUEST_CHANGES are not dispatchable.
[[ "$event" == COMMENT ]] || problem "event must be COMMENT, got '${event:-<missing>}'"

[[ "$reviewed_head_sha" =~ ^[0-9a-f]{40}$ ]] \
  || problem "reviewed_head_sha must be a full 40-character SHA"

# --- head freshness ------------------------------------------------------
if current_head="$(gh api "repos/${repository}/pulls/${pr_number}" --jq .head.sha 2>/dev/null)"; then
  current_head="$(printf '%s' "$current_head" | tr -d '[:space:]')"
  [[ "$current_head" == "$reviewed_head_sha" ]] \
    || problem "reviewed_head_sha is stale: manifest ${reviewed_head_sha}, pull request head ${current_head}"
else
  problem "could not read the pull request head"
fi

# --- inline anchors in the diff -----------------------------------------
# Only right-hand-side lines can carry an inline comment. Walk the hunks and
# record every right-hand line number per file: added and context lines advance
# the right-hand counter, removed lines do not. The counter is reset by each
# hunk header, which is why a manifest anchored between two hunks is rejected
# even though the line exists in the file.
if diff_text="$(gh pr diff "$pr_number" --repo "$repository" 2>/dev/null)"; then
  # `+++ ` is a file header only OUTSIDE a hunk. Inside one it is an added line
  # whose own text begins with `++`, which the diff format renders identically.
  # Without the hunk flag such a line is adopted as the current path and every
  # later right-hand line of the file is recorded under a path the diff never
  # contained, so a valid anchor is rejected. `diff --git` reopens the header
  # region; it cannot be confused with content, which always carries a prefix.
  diff_lines="$(awk '
    /^diff --git / { in_hunk = 0; file = ""; next }
    /^@@ /       { match($0, /\+[0-9]+/); right = substr($0, RSTART + 1, RLENGTH - 1) + 0; in_hunk = 1; next }
    /^\+\+\+ /   { if (!in_hunk) { file = $2; sub(/^b\//, "", file); next } }
    file == ""   { next }
    /^\+/        { print file ":" right; right++; next }
    /^-/         { next }
    /^\\/        { next }
    /^ /         { print file ":" right; right++; next }
  ' <<<"$diff_text")"
  while IFS= read -r anchor; do
    [[ -n "$anchor" ]] || continue
    grep -qxF "$anchor" <<<"$diff_lines" \
      || problem "inline comment is not on the right-hand side of the diff: ${anchor}"
  done < <(jq -r '.[] | "\(.path):\(.line)"' <<<"$inline_comments" 2>/dev/null)
else
  problem "could not read the pull request diff"
fi

# --- reply targets -------------------------------------------------------
readonly expected_pr_url="https://api.github.com/repos/${repository}/pulls/${pr_number}"
while IFS= read -r comment_id; do
  [[ -n "$comment_id" ]] || continue
  if ! target="$(gh api "repos/${repository}/pulls/comments/${comment_id}" 2>/dev/null)"; then
    problem "reply target ${comment_id} could not be read"
    continue
  fi
  [[ "$(jq -r '.pull_request_url // empty' <<<"$target")" == "$expected_pr_url" ]] \
    || problem "reply target ${comment_id} does not belong to this pull request"
  [[ -z "$(jq -r '.in_reply_to_id // empty' <<<"$target")" ]] \
    || problem "reply target ${comment_id} is itself a reply; reply to the top-level comment of the thread"
done < <(jq -r '.[] | .comment_id' <<<"$replies" 2>/dev/null)

# --- resolution targets --------------------------------------------------
if [[ "$(jq length <<<"$resolve_thread_ids" 2>/dev/null || echo 0)" -gt 0 ]]; then
  thread_ids="$(
    cursor=""
    while :; do
      args=(-f query='query($owner: String!, $name: String!, $number: Int!, $after: String) { repository(owner: $owner, name: $name) { pullRequest(number: $number) { reviewThreads(first: 100, after: $after) { nodes { id } pageInfo { hasNextPage endCursor } } } } }' -f owner="$owner" -f name="$name" -F number="$pr_number")
      [[ -z "$cursor" ]] || args+=(-f after="$cursor")
      page="$(gh api graphql "${args[@]}")" || exit 1
      jq -r '.data.repository.pullRequest.reviewThreads.nodes[].id' <<<"$page"
      [[ "$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage' <<<"$page")" == true ]] || break
      cursor="$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor' <<<"$page")"
    done
  )" || thread_ids=""
  if [[ -z "$thread_ids" ]]; then
    problem "could not read the pull request review threads"
  else
    while IFS= read -r thread_id; do
      [[ -n "$thread_id" ]] || continue
      grep -qxF "$thread_id" <<<"$thread_ids" \
        || problem "resolve_thread_ids entry ${thread_id} is not a review thread of this pull request"
    done < <(jq -r '.[]' <<<"$resolve_thread_ids" 2>/dev/null)
  fi
fi

[[ "$failures" == 0 ]] || exit 1
printf 'manifest ok: inline=%s replies=%s resolutions=%s\n' \
  "$(jq length <<<"$inline_comments")" \
  "$(jq length <<<"$replies")" \
  "$(jq length <<<"$resolve_thread_ids")"
