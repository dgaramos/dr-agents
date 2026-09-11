#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/publication-outcome.sh"
outcome_heading "${EXPECTED_AUTHOR:-publisher} pull request publisher"

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${TITLE:?TITLE is required}"
: "${BODY:?BODY is required}"
: "${HEAD_BRANCH:?HEAD_BRANCH is required}"
: "${BASE_BRANCH:?BASE_BRANCH is required}"
: "${EXPECTED_AUTHOR:?EXPECTED_AUTHOR is required}"
: "${PUBLISHER_APP_SLUG:?PUBLISHER_APP_SLUG is required}"
[[ "$PUBLISHER_APP_SLUG" == "${EXPECTED_AUTHOR%\[bot\]}" ]] || outcome_not_published "unexpected authenticated app"
[[ "$HEAD_BRANCH" != "$BASE_BRANCH" ]] || outcome_not_published "head and base must differ"
existing="$(gh api --method GET "repos/${GITHUB_REPOSITORY}/pulls" -f state=open -f "head=${GITHUB_REPOSITORY%%/*}:${HEAD_BRANCH}" -f "base=${BASE_BRANCH}")"
count="$(jq length <<<"$existing")"
if [[ "$count" == 0 ]]; then
  result="$(jq -n --arg title "$TITLE" --arg body "$BODY" --arg head "$HEAD_BRANCH" --arg base "$BASE_BRANCH" \
    '{title:$title, body:$body, head:$head, base:$base}' | gh api --method POST "repos/${GITHUB_REPOSITORY}/pulls" --input -)"
elif [[ "$count" == 1 ]]; then
  result="$(jq '.[0]' <<<"$existing")"
else
  outcome_not_published "ambiguous existing pull request"
fi
# A pull request exists from here on: either the POST above created one, or an
# open one was found. Name it before verifying, so a red job cannot be read as
# "nothing was published".
number="$(jq -er .number <<<"$result")"
outcome_resource "$(jq -r '"[#\(.number)](\(.html_url))"' <<<"$result")"
jq -e --arg actor "$EXPECTED_AUTHOR" --arg repo "$GITHUB_REPOSITORY" --arg head "$HEAD_BRANCH" --arg base "$BASE_BRANCH" \
  '.user.login == $actor and .head.ref == $head and .base.ref == $base and .base.repo.full_name == $repo and .head.repo.full_name == $repo' <<<"$result" >/dev/null || outcome_published_unverified "PR actor or target verification failed"
observed="$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${number}")"
jq -e --arg actor "$EXPECTED_AUTHOR" --arg title "$TITLE" --arg body "$BODY" --arg head "$HEAD_BRANCH" --arg base "$BASE_BRANCH" \
  '.user.login == $actor and .title == $title and .body == $body and .head.ref == $head and .base.ref == $base' <<<"$observed" >/dev/null || outcome_published_unverified "PR verification failed; inspect the existing PR before retrying"
outcome_published_ok
jq -r '"Created and verified PR #\(.number): \(.html_url)"' <<<"$observed"
