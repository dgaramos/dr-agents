#!/usr/bin/env bash
# Sweep what a previous smoke run left behind (dr-agents#267).
#
# A cleanup job with `if: always()` covers a failed run. It does not cover a
# cancelled run, a runner that died, or a workflow that was force-cancelled
# twice -- and those are exactly the cases that accumulate litter. So the sweep
# runs at the *start* of every run as well, which is what makes a mid-run death
# self-healing rather than permanent.
#
# It never fails the run. A leftover it cannot remove is named in the output and
# in the step summary instead, because reddening the run here would mask the
# result of the dispatch the run exists to measure (AC-04).
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

readonly prefix="${SMOKE_BRANCH_PREFIX:-smoke/publishers-}"
readonly max_age="${SMOKE_MAX_AGE_SECONDS:-7200}"
readonly keep_branch="${SMOKE_KEEP_BRANCH:-}"

summary() { [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && echo "$1" >>"$GITHUB_STEP_SUMMARY"; return 0; }

# Portable "now minus max_age" as an ISO-8601 UTC stamp, so stale pull requests
# can be found by lexicographic comparison against `created_at`. GNU date first,
# BSD date second -- this script runs on the runner and on a contributor's Mac.
threshold="$(date -u -d "@$(( $(date -u +%s) - max_age ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -v-"${max_age}"S +%Y-%m-%dT%H:%M:%SZ)"

stranded=()

# Close stale smoke pull requests. A PR younger than the threshold belongs to a
# run still in flight; the concurrency group makes that rare, but not deleting
# another run's work is worth the check.
while IFS=$'\t' read -r number branch created_at; do
  [[ -n "${number:-}" ]] || continue
  [[ "$branch" != "$keep_branch" ]] || continue
  if [[ "$created_at" > "$threshold" ]]; then
    echo "skipping pull request #${number} (${branch}): newer than the stale threshold"
    continue
  fi
  if gh api --method PATCH "repos/${GITHUB_REPOSITORY}/pulls/${number}" -f state=closed >/dev/null 2>&1; then
    echo "closed stale smoke pull request #${number} (${branch})"
  else
    echo "could not close pull request #${number} (${branch})" >&2
    stranded+=("pull request #${number} (${branch})")
  fi
done < <(gh api "repos/${GITHUB_REPOSITORY}/pulls" --paginate \
  --jq ".[] | select(.head.ref | startswith(\"${prefix}\")) | [.number, .head.ref, .created_at] | @tsv" 2>/dev/null || true)

# Delete stale smoke branches, including any that never got a pull request --
# the run that died between pushing the branch and creating the PR leaves
# exactly that, and it is still litter.
while IFS= read -r ref; do
  [[ -n "${ref:-}" ]] || continue
  branch="${ref#refs/heads/}"
  [[ "$branch" != "$keep_branch" ]] || { echo "sparing the current run's branch: ${branch}"; continue; }
  if gh api --method DELETE "repos/${GITHUB_REPOSITORY}/git/refs/heads/${branch}" >/dev/null 2>&1; then
    echo "deleted stale smoke branch ${branch}"
  else
    echo "could not delete branch ${branch}" >&2
    stranded+=("branch ${branch}")
  fi
done < <(gh api "repos/${GITHUB_REPOSITORY}/git/matching-refs/heads/${prefix}" --paginate \
  --jq '.[].ref' 2>/dev/null || true)

# Delete the smoke comments left on the permanent target issues.
#
# This is what makes the issue-comment route (dr-agents#269) safe to smoke-test
# without a disposable target. The original design note assumed an App cannot
# delete a comment the way it cannot delete an issue -- that is wrong, and
# measuring it changed the design. `DELETE /repos/{o}/{r}/issues/comments/{id}`
# requires only `Issues: write`, the same permission the publisher already holds
# to create the comment. An issue really is undeletable by an App; a comment on
# one is not.
#
# So the smoke run comments on the permanent `smoke-target` issue and this sweep
# removes it, with no second disposable target and no accumulation. Comments are
# matched by author and age rather than by an identifier threaded out of the
# publisher job, for the same reason the branch sweep is: a run that dies before
# it can report anything still gets cleaned up by the next run.
readonly smoke_label="${SMOKE_TARGET_LABEL:-smoke-target}"
while IFS= read -r issue_number; do
  [[ -n "${issue_number:-}" ]] || continue
  while IFS=$'\t' read -r comment_id created_at author; do
    [[ -n "${comment_id:-}" ]] || continue
    if [[ "$created_at" > "$threshold" ]]; then
      echo "skipping comment ${comment_id} on #${issue_number}: newer than the stale threshold"
      continue
    fi
    if gh api --method DELETE "repos/${GITHUB_REPOSITORY}/issues/comments/${comment_id}" >/dev/null 2>&1; then
      echo "deleted stale smoke comment ${comment_id} by ${author} on #${issue_number}"
    else
      echo "could not delete comment ${comment_id} on #${issue_number}" >&2
      stranded+=("comment ${comment_id} on issue #${issue_number}")
    fi
  done < <(gh api "repos/${GITHUB_REPOSITORY}/issues/${issue_number}/comments" --paginate \
    --jq '.[] | select(.user.login | endswith("-dr[bot]")) | [.id, .created_at, .user.login] | @tsv' 2>/dev/null || true)
done < <(gh api "repos/${GITHUB_REPOSITORY}/issues" --paginate \
  -f "labels=${smoke_label}" -f state=all \
  --jq '.[].number' 2>/dev/null || true)

if (( ${#stranded[@]} > 0 )); then
  summary "### Smoke resources left behind"
  summary ""
  echo "the following smoke resources could not be removed and need attention:" >&2
  for item in "${stranded[@]}"; do
    echo "  - ${item}" >&2
    summary "- ${item}"
  done
fi
echo "smoke reaper finished"
