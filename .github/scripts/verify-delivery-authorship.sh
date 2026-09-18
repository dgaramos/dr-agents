#!/usr/bin/env bash
# Verify that an agent delivery PR was published by the adapter App.
#
# dr-agents#315 shipped four delivery PRs. The first was authored by
# claudio-dr[bot]; the next three were created with the maintainer's personal
# `gh` account after a Projects-only fallback silently widened to PR creation
# and commit authorship. The routing contract already forbade this
# ("a personal issue fallback does not authorize bypassing an available App for
# PRs, metadata, or reviews") and the ship contract already required verifying
# the PR's author -- but nothing observed the result, so four handoffs read
# clean. This script is that observation.
#
# Scope: branches named <issue-number>-<type>/<slug>, the convention CLAUDE.md
# reserves for agent issue execution. Human branches are untouched.
#
# Escape hatch: a PR carrying the `human-delivery` label is exempt, so a
# maintainer can still hand-open a PR on a delivery branch deliberately.
set -euo pipefail

branch="${1:?head branch required}"
author="${2:?PR author login required}"
labels="${3-}"

readonly delivery_branch='^[0-9]+-(feat|fix|docs|refactor|chore|test|build|ci)/'

if ! printf '%s' "$branch" | grep -Eq "$delivery_branch"; then
  echo "not a delivery branch: $branch -- authorship not checked"
  exit 0
fi

# Compare labels exactly, one per field. `grep -w` is not an exact match here:
# `-` is not a word constituent, so `human-delivery-request` would satisfy a
# word match for `human-delivery` and exempt a PR that was never exempted.
IFS=',' read -r -a label_list <<<"$labels"
for label in "${label_list[@]+"${label_list[@]}"}"; do
  if [ "${label// /}" = "human-delivery" ]; then
    echo "delivery branch $branch is labelled human-delivery -- exempt"
    exit 0
  fi
done

# App authorship surfaces as `app/<slug>` or `<slug>[bot]` depending on the
# endpoint that reported it; accept either rather than pinning one shape.
if printf '%s' "$author" | grep -Eq '^app/|\[bot\]$'; then
  echo "delivery branch $branch published by App actor $author"
  exit 0
fi

cat >&2 <<MSG
delivery PR authorship check failed

  branch: $branch
  author: $author

A branch matching <issue-number>-<type>/<slug> is agent issue execution, and
its PR must be published by the adapter App. This PR was opened by a personal
account.

An authorized fallback for Projects, metadata, or an issue does not authorize
creating the PR outside the App -- see
core/pr-review/references/publication-routing-contract.md rule 2 and
core/issue-workflow/references/ship-change-contract.md step 4.

If the App publisher is genuinely unavailable, say so in the PR body and add
the 'human-delivery' label. Do not let the fallback pass unreported.
MSG
exit 1
