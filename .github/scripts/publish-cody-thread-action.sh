#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/publication-outcome.sh"
outcome_heading "${EXPECTED_AUTHOR:-publisher} thread publisher"

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${THREAD_ID:?THREAD_ID is required}"
: "${THREAD_ACTION:?THREAD_ACTION is required}"
: "${EXPECTED_AUTHOR:?EXPECTED_AUTHOR is required}"
: "${PUBLISHER_APP_SLUG:?PUBLISHER_APP_SLUG is required}"

[[ "$PR_NUMBER" =~ ^[1-9][0-9]*$ ]] || outcome_not_published "pr_number must be a positive integer"
[[ -n "$THREAD_ID" ]] || outcome_not_published "thread_id is required"
[[ "$PUBLISHER_APP_SLUG" == "${EXPECTED_AUTHOR%\[bot\]}" ]] || outcome_not_published "unexpected authenticated app"
case "$THREAD_ACTION" in
  reply) : "${BODY:?body is required}" ;;
  resolve) ;;
  *) outcome_not_published "unsupported thread action" ;;
esac

readonly expected_repository="$GITHUB_REPOSITORY"
found=false
cursor=""
while :; do
  args=(-f query='query($owner: String!, $name: String!, $number: Int!, $after: String) { repository(owner: $owner, name: $name) { pullRequest(number: $number) { reviewThreads(first: 100, after: $after) { nodes { id } pageInfo { hasNextPage endCursor } } } } }' -f owner="${GITHUB_REPOSITORY%%/*}" -f name="${GITHUB_REPOSITORY##*/}" -F number="$PR_NUMBER")
  [[ -z "$cursor" ]] || args+=(-f after="$cursor")
  threads="$(gh api graphql "${args[@]}")"
  if jq -e --arg thread "$THREAD_ID" '.data.repository.pullRequest.reviewThreads.nodes | any(.id == $thread)' <<<"$threads" >/dev/null; then found=true; break; fi
  [[ "$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage' <<<"$threads")" == true ]] || break
  cursor="$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor' <<<"$threads")"
done
[[ "$found" == true ]] || outcome_not_published "thread target mismatch"

if [[ "$THREAD_ACTION" == reply ]]; then
  result="$(gh api graphql -f query='mutation($thread: ID!, $body: String!) { addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $thread, body: $body}) { comment { author { login } pullRequest { number repository { nameWithOwner } } } } }' -f thread="$THREAD_ID" -f body="$BODY")"
  outcome_resource "reply on thread \`${THREAD_ID}\` of #${PR_NUMBER}"
  reply_author="$(jq -r '.data.addPullRequestReviewThreadReply.comment.author.login' <<<"$result")"
  [[ "${reply_author%\[bot\]}" == "${EXPECTED_AUTHOR%\[bot\]}" ]] || outcome_published_unverified "unexpected reply author"
  [[ "$(jq -r '.data.addPullRequestReviewThreadReply.comment.pullRequest.number' <<<"$result")" == "$PR_NUMBER" ]] || outcome_published_unverified "reply target mismatch"
  [[ "$(jq -r '.data.addPullRequestReviewThreadReply.comment.pullRequest.repository.nameWithOwner' <<<"$result")" == "$expected_repository" ]] || outcome_published_unverified "reply repository mismatch"
else
  outcome_resource "resolution of thread \`${THREAD_ID}\` on #${PR_NUMBER}"
  gh api graphql -f query='mutation($thread: ID!) { resolveReviewThread(input: {threadId: $thread}) { thread { isResolved } } }' -f thread="$THREAD_ID" --jq '.data.resolveReviewThread.thread.isResolved' | grep -qx true \
    || outcome_published_unverified "the resolve mutation did not report the thread as resolved"
fi

outcome_published_ok
printf 'Publication report: action=%s pr=%s thread=%s\n' "$THREAD_ACTION" "$PR_NUMBER" "$THREAD_ID"
