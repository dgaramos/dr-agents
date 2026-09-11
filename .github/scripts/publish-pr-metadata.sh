#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/publication-outcome.sh"
outcome_heading "${EXPECTED_AUTHOR:-publisher} PR metadata publisher"

: "${PR_NUMBER:?PR_NUMBER is required}"
: "${BASE_BRANCH:?BASE_BRANCH is required}"
: "${EXPECTED_AUTHOR:?EXPECTED_AUTHOR is required}"
: "${PUBLISHER_APP_SLUG:?PUBLISHER_APP_SLUG is required}"
metadata_helper="${METADATA_HELPER:-core/issue-workflow/scripts/apply-pr-metadata.sh}"

[[ "$PUBLISHER_APP_SLUG" == "${EXPECTED_AUTHOR%\[bot\]}" ]] || outcome_not_published "unexpected authenticated app"

jq -e 'type == "array" and all(.[]; type == "string" and length > 0)' <<<"${LABELS_JSON:-[]}" >/dev/null || outcome_not_published "invalid labels_json"
jq -e 'type == "array" and all(.[]; type == "string" and length > 0)' <<<"${ASSIGNEES_JSON:-[]}" >/dev/null || outcome_not_published "invalid assignees_json"
jq -e 'type == "array" and all(.[]; type == "string" and length > 0)' <<<"${REVIEWERS_JSON:-[]}" >/dev/null || outcome_not_published "invalid reviewers_json"
mapfile -t labels < <(jq -r '.[]' <<<"${LABELS_JSON:-[]}")
mapfile -t assignees < <(jq -r '.[]' <<<"${ASSIGNEES_JSON:-[]}")
mapfile -t reviewers < <(jq -r '.[]' <<<"${REVIEWERS_JSON:-[]}")

core_args=(
  --repo "$GITHUB_REPOSITORY"
  --pr "$PR_NUMBER"
  --base "$BASE_BRANCH"
)
for label in "${labels[@]}"; do core_args+=(--label "$label"); done
for assignee in "${assignees[@]}"; do core_args+=(--assignee "$assignee"); done
for reviewer in "${reviewers[@]}"; do core_args+=(--reviewer "$reviewer"); done
[[ -z "${MILESTONE_NUMBER:-}" ]] || core_args+=(--milestone "$MILESTONE_NUMBER")

# The helper mutates as it goes, so a failure can leave metadata partly
# applied. Name the pull request before running it: everything from here is a
# published state, never `not-published`.
outcome_resource "pull request #${PR_NUMBER}"
if bash "$metadata_helper" "${core_args[@]}"; then
  echo "core metadata (labels/milestone/assignee) applied and verified"
else
  echo "ERROR: core metadata step failed; labels/milestone/assignee may be incomplete" >&2
  outcome_published_unverified "core metadata step failed; labels/milestone/assignee may be incomplete"
fi

if [[ -n "${PROJECT_OWNER:-}${PROJECT_NUMBER:-}${PROJECT_STATUS:-}" ]]; then
  if [[ -z "${PROJECT_OWNER:-}" || -z "${PROJECT_NUMBER:-}" || -z "${PROJECT_STATUS:-}" ]]; then
    echo "WARNING: project owner, number, and status must be supplied together — skipping Project step" >&2
  elif [[ -z "${PROJECT_GH_TOKEN:-}" ]]; then
    echo "WARNING: Project pending; no organization Projects token is available. Use the authorized local gh account for user-owned Projects." >&2
  else
    project_args=(
      --repo "$GITHUB_REPOSITORY"
      --pr "$PR_NUMBER"
      --base "$BASE_BRANCH"
      --project-owner "$PROJECT_OWNER"
      --project-number "$PROJECT_NUMBER"
      --project-status "$PROJECT_STATUS"
    )
    if GH_TOKEN="$PROJECT_GH_TOKEN" bash "$metadata_helper" "${project_args[@]}"; then
      echo "Project V2 step applied and verified"
    else
      echo "WARNING: Project pending; verify organization Projects access and target configuration. Ordinary metadata was applied successfully." >&2
    fi
  fi
fi

# The Project step is advisory: it warns and does not fail the publisher, by a
# prior deliberate decision. Its state is recorded above rather than changing
# the verdict.
outcome_published_ok
