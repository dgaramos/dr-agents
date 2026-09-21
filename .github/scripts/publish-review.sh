#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/publication-outcome.sh"
. "$(dirname "${BASH_SOURCE[0]}")/publication-input.sh"
outcome_heading "${EXPECTED_AUTHOR:-publisher} review publisher"

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${REVIEW_EVENT:?REVIEW_EVENT is required}"
: "${REVIEWED_HEAD_SHA:?REVIEWED_HEAD_SHA is required}"
: "${EXPECTED_AUTHOR:?EXPECTED_AUTHOR is required}"
: "${PUBLISHER_APP_SLUG:?PUBLISHER_APP_SLUG is required}"

readonly inline_comments_json="${INLINE_COMMENTS_JSON:-[]}"
readonly replies_json="${REPLIES_JSON:-[]}"
readonly resolve_thread_ids_json="${RESOLVE_THREAD_IDS_JSON:-[]}"
[[ "$PR_NUMBER" =~ ^[1-9][0-9]*$ ]] || outcome_not_published "pr_number must be a positive integer"
[[ "$REVIEWED_HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || outcome_not_published "reviewed_head_sha must be a full SHA"
[[ "$PUBLISHER_APP_SLUG" == "${EXPECTED_AUTHOR%\[bot\]}" ]] || outcome_not_published "unexpected authenticated app"
case "$REVIEW_EVENT" in APPROVE) expected_state=APPROVED ;; COMMENT) expected_state=COMMENTED ;; REQUEST_CHANGES) expected_state=CHANGES_REQUESTED ;; *) outcome_not_published "unsupported review event" ;; esac
jq -e 'type == "array" and all(.[]; type == "object" and (.path | type == "string" and length > 0) and (.line | type == "number" and floor == . and . > 0) and (.body | type == "string" and length > 0))' <<<"$inline_comments_json" >/dev/null || outcome_not_published "invalid inline_comments_json"
jq -e 'type == "array" and all(.[]; type == "object" and (.comment_id | type == "number" and floor == . and . > 0) and (.body | type == "string" and length > 0))' <<<"$replies_json" >/dev/null || outcome_not_published "invalid replies_json"
jq -e 'type == "array" and all(.[]; type == "string" and length > 0)' <<<"$resolve_thread_ids_json" >/dev/null || outcome_not_published "invalid resolve_thread_ids_json"
readonly expected_pr_url="https://api.github.com/repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}"
[[ "$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}" --jq .head.sha)" == "$REVIEWED_HEAD_SHA" ]] || outcome_not_published "PR head changed since review"
publish_review=false
require_body_contents "${REVIEW_BODY:-}"
if [[ -n "${REVIEW_BODY:-}" ]] || [[ "$(jq length <<<"$inline_comments_json")" -gt 0 ]]; then publish_review=true; fi
[[ "$publish_review" == true || "$(jq length <<<"$replies_json")" -gt 0 || "$(jq length <<<"$resolve_thread_ids_json")" -gt 0 ]] || outcome_not_published "provide a review body, inline finding, reply, or resolution"
while IFS= read -r reply; do
  comment_id="$(jq -r '.comment_id' <<<"$reply")"
  [[ "$(gh api "repos/${GITHUB_REPOSITORY}/pulls/comments/${comment_id}" --jq .pull_request_url)" == "$expected_pr_url" ]] || outcome_not_published "reply target mismatch"
  [[ -z "$(gh api "repos/${GITHUB_REPOSITORY}/pulls/comments/${comment_id}" --jq '.in_reply_to_id // empty')" ]] || outcome_not_published "reply target must be a top-level review comment"
done < <(jq -c '.[]' <<<"$replies_json")
# One paged read of the PR's threads serves both the resolution check below and
# the reply-to-thread mapping the batched route needs. `addPullRequestReviewThreadReply`
# takes a thread node id, while the manifest names a top-level comment id.
# NOTE: this thread-paging query, and the resolution-target loop below, are two
# of five sites carrying the same query; the other three are the scripts under
# core/pr-review/scripts/. Consolidating them is deferred, not overlooked.
thread_index_file="$(mktemp)"
index_threads() {
  local cursor="" page
  : >"$thread_index_file"
  while :; do
    local args=(-f query='query($owner: String!, $name: String!, $number: Int!, $after: String) { repository(owner: $owner, name: $name) { pullRequest(number: $number) { id reviewThreads(first: 100, after: $after) { nodes { id comments(first: 1) { nodes { databaseId } } } pageInfo { hasNextPage endCursor } } } } }' -f owner="${GITHUB_REPOSITORY%%/*}" -f name="${GITHUB_REPOSITORY##*/}" -F number="$PR_NUMBER")
    [[ -z "$cursor" ]] || args+=(-f after="$cursor")
    page="$(gh api graphql "${args[@]}")"
    jq -r '.data.repository.pullRequest.reviewThreads.nodes[] | "\(.comments.nodes[0].databaseId // "none") \(.id)"' <<<"$page" >>"$thread_index_file"
    [[ "$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage' <<<"$page")" == true ]] || break
    cursor="$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor' <<<"$page")"
  done
}
thread_for_comment() {
  awk -v want="$1" '$1 == want { print $2; exit }' "$thread_index_file"
}

# The second of this file's two query sites (see the note above).
while IFS= read -r thread_id; do
  cursor=""; found=false
  while :; do
    args=(-f query='query($owner: String!, $name: String!, $number: Int!, $after: String) { repository(owner: $owner, name: $name) { pullRequest(number: $number) { reviewThreads(first: 100, after: $after) { nodes { id } pageInfo { hasNextPage endCursor } } } } }' -f owner="${GITHUB_REPOSITORY%%/*}" -f name="${GITHUB_REPOSITORY##*/}" -F number="$PR_NUMBER")
    [[ -z "$cursor" ]] || args+=(-f after="$cursor")
    threads="$(gh api graphql "${args[@]}")"
    if jq -e --arg thread "$thread_id" '.data.repository.pullRequest.reviewThreads.nodes | any(.id == $thread)' <<<"$threads" >/dev/null; then found=true; break; fi
    [[ "$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage' <<<"$threads")" == true ]] || break
    cursor="$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor' <<<"$threads")"
  done
  [[ "$found" == true ]] || outcome_not_published "resolution target mismatch"
done < <(jq -r '.[]' <<<"$resolve_thread_ids_json")
# A review comment always belongs to a review. The REST reply route has no
# pending review to attach to, so GitHub creates one implicitly and submits it
# empty -- the shell is the container the reply required, not a side effect
# (dr-agents#326, docs/spike-single-event-review.md). When this pass is
# submitting a review anyway, the replies ride it and no shell appears.
batched=false
if [[ "$publish_review" == true && "$(jq length <<<"$replies_json")" -gt 0 ]]; then batched=true; fi

if [[ "$batched" == true ]]; then
  index_threads
  # Map every reply to its thread BEFORE any mutation: a reply whose thread
  # cannot be found must fail while `not-published` is still honest.
  reply_plan="$(mktemp)"
  while IFS= read -r reply; do
    comment_id="$(jq -r '.comment_id' <<<"$reply")"
    thread_id="$(thread_for_comment "$comment_id")"
    [[ -n "$thread_id" ]] || outcome_not_published "reply target has no review thread on this pull request"
    jq -cn --arg thread "$thread_id" --arg body "$(jq -r '.body' <<<"$reply")" '{thread: $thread, body: $body}' >>"$reply_plan"
  done < <(jq -c '.[]' <<<"$replies_json")

  pr_node_id="$(gh api graphql -f query='query($owner: String!, $name: String!, $number: Int!) { repository(owner: $owner, name: $name) { pullRequest(number: $number) { id } } }' -f owner="${GITHUB_REPOSITORY%%/*}" -f name="${GITHUB_REPOSITORY##*/}" -F number="$PR_NUMBER" --jq '.data.repository.pullRequest.id')"
  [[ -n "$pr_node_id" ]] || outcome_not_published "could not resolve the pull request node id"

  # `threads` carries the inline findings; a complex variable needs a JSON body
  # rather than -f, which would send the array as a string.
  jq -n --arg pr "$pr_node_id" --arg body "${REVIEW_BODY:-}" --arg commit "$REVIEWED_HEAD_SHA" --argjson comments "$inline_comments_json" '{
    query: "mutation($pr: ID!, $body: String!, $commit: GitObjectID!, $threads: [DraftPullRequestReviewThread!]) { addPullRequestReview(input: {pullRequestId: $pr, body: $body, commitOID: $commit, threads: $threads}) { pullRequestReview { id } } }",
    variables: {pr: $pr, body: $body, commit: $commit, threads: ($comments | map({path: .path, line: .line, side: "RIGHT", body: .body}))}
  }' > pending-review.json
  pending_id="$(gh api graphql --input pending-review.json --jq '.data.addPullRequestReview.pullRequestReview.id')"
  [[ -n "$pending_id" ]] || outcome_not_published "could not open a pending review"
  # From here a pending review exists. It is invisible until submitted, but it
  # is state, so nothing below may report `not-published`.

  while IFS= read -r planned; do
    gh api graphql -f query='mutation($review: ID!, $thread: ID!, $body: String!) { addPullRequestReviewThreadReply(input: {pullRequestReviewId: $review, pullRequestReviewThreadId: $thread, body: $body}) { comment { databaseId } } }' -f review="$pending_id" -f thread="$(jq -r '.thread' <<<"$planned")" -f body="$(jq -r '.body' <<<"$planned")" > replied.json || outcome_published_unverified "a batched reply failed after the pending review was opened"
  done <"$reply_plan"

  gh api graphql -f query='mutation($review: ID!, $event: PullRequestReviewEvent!) { submitPullRequestReview(input: {pullRequestReviewId: $review, event: $event}) { pullRequestReview { databaseId state } } }' -f review="$pending_id" -f event="$REVIEW_EVENT" > submitted.json || outcome_published_unverified "the pending review carrying the replies could not be submitted"
  submitted_id="$(jq -r '.data.submitPullRequestReview.pullRequestReview.databaseId' submitted.json)"
  gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/reviews/${submitted_id}" > created-review.json
  # Mutation point 1 of 3. Named before verification, so a failure below cannot
  # be read as "no review was posted".
  outcome_resource "review $(jq -r '.html_url // "on #'"${PR_NUMBER}"'"' created-review.json)"
  outcome_note "replies batched into the review: $(jq length <<<"$replies_json") (no review shells)"
  [[ "$(jq -r '.user.login' created-review.json)" == "$EXPECTED_AUTHOR" ]] || outcome_published_unverified "unexpected review author"
  [[ "$(jq -r '.pull_request_url' created-review.json)" == "$expected_pr_url" ]] || outcome_published_unverified "review target mismatch"
  [[ "$(jq -r '.state' created-review.json)" == "$expected_state" ]] || outcome_published_unverified "unexpected review state"
else
  if [[ "$publish_review" == true ]]; then
    jq -n --arg event "$REVIEW_EVENT" --arg body "${REVIEW_BODY:-}" --arg commit_id "$REVIEWED_HEAD_SHA" --argjson comments "$inline_comments_json" '{event: $event, body: $body, commit_id: $commit_id} + (if ($comments | length) == 0 then {} else {comments: ($comments | map({path, line, side: "RIGHT", body}))} end)' > review.json
    gh api --method POST "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/reviews" --input review.json > created-review.json
    # Mutation point 1 of 3. Named before verification, so a failure below cannot
    # be read as "no review was posted".
    outcome_resource "review $(jq -r '.html_url // "on #'"${PR_NUMBER}"'"' created-review.json)"
    [[ "$(jq -r '.user.login' created-review.json)" == "$EXPECTED_AUTHOR" ]] || outcome_published_unverified "unexpected review author"
    [[ "$(jq -r '.pull_request_url' created-review.json)" == "$expected_pr_url" ]] || outcome_published_unverified "review target mismatch"
    [[ "$(jq -r '.state' created-review.json)" == "$expected_state" ]] || outcome_published_unverified "unexpected review state"
  fi
  # Replies with no review to ride: the REST route is the only one available and
  # each reply emits a body-less shell. dr-agents#319 tolerates them; state it
  # rather than leaving the reader to discover it.
  if [[ "$(jq length <<<"$replies_json")" -gt 0 ]]; then
    outcome_note "replies posted through the REST route: each emits a body-less review event"
  fi
  while IFS= read -r reply; do
    comment_id="$(jq -r '.comment_id' <<<"$reply")"; reply_body="$(jq -r '.body' <<<"$reply")"
    gh api --method POST "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/comments" -f body="$reply_body" -F in_reply_to="$comment_id" > created-reply.json
    # Mutation point 2 of 3, once per reply. A later reply failing leaves the
    # earlier ones published, which is why this is never `not-published`.
    outcome_resource "reply $(jq -r '.html_url // "to comment '"${comment_id}"'"' created-reply.json)"
    [[ "$(jq -r '.user.login' created-reply.json)" == "$EXPECTED_AUTHOR" ]] || outcome_published_unverified "unexpected reply author"
  done < <(jq -c '.[]' <<<"$replies_json")
fi
resolved_count=0
while IFS= read -r thread_id; do
  if resolve_out="$(gh api graphql -f query='mutation($thread: ID!) { resolveReviewThread(input: {threadId: $thread}) { thread { isResolved } } }' -f thread="$thread_id" --jq '.data.resolveReviewThread.thread.isResolved' 2>&1)" && [[ "$resolve_out" == "true" ]]; then
    resolved_count=$((resolved_count + 1))
  else
    echo "warning: could not resolve thread ${thread_id} (skipped): ${resolve_out}" >&2
  fi
done < <(jq -r '.[]' <<<"$resolve_thread_ids_json")
# Mutation point 3 of 3. Resolution is best-effort by a deliberate earlier
# decision: a failure here warns and the script still exits 0. So the outcome
# stays `published-ok` -- emitting `published-unverified` on a zero exit would
# break the invariant the issue publisher sets, where that outcome always
# accompanies exit 1 and means "a resource exists, do not republish". The
# explicit count is what stops a partial result from hiding behind "ok".
outcome_note "resolutions: ${resolved_count}/$(jq length <<<"$resolve_thread_ids_json")"
outcome_published_ok
printf 'Publication report: review=%s inline=%s replies=%s resolutions=%s/%s\n' "$publish_review" "$(jq length <<<"$inline_comments_json")" "$(jq length <<<"$replies_json")" "$resolved_count" "$(jq length <<<"$resolve_thread_ids_json")"
