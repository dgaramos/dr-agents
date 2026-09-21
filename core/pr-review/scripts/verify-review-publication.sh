#!/usr/bin/env bash
# Verify that an authorized review was actually published as the manifest said.
#
# The hard part is one distinction, and it is conditional on the route.
#
# A review comment always belongs to a review. When a reply is posted over REST
# there is no pending review to attach it to, so the platform creates one and
# submits it empty. Those shells are attributed to the reviewer and sit on the
# reviewed head, so a naive "exactly one review by this actor" check fails a
# correct publication. They are containers the platform made, not events the
# reviewer submitted.
#
# But the publisher only takes that route when the pass has no review to carry
# the replies. When it does, the replies ride the submitted review and no shell
# is created -- so tolerating one there would tolerate exactly the duplicate
# this script exists to catch. The route is therefore recomputed from the
# manifest, with the publisher's own predicate, and the tolerance applies only
# where a shell can legitimately arise.
#
# What must fail on either route is a genuine second review. A review is real --
# never a shell -- if it has a body OR carries inline comments of its own, so an
# extra review with content is reported as `unexpected additional review` even
# where a shell in the same position would have been allowed.
#
# NOTE: the review-thread paging query below is duplicated in
# load-review-threads.sh and validate-review-manifest.sh, which the issues
# declare independent of one another. dr-agents#322 owns consolidating the three
# query sites into one.
set -euo pipefail

[[ $# == 2 ]] || { echo "usage: verify-review-publication.sh MANIFEST_PATH EXPECTED_ACTOR" >&2; exit 2; }
readonly manifest="$1"
readonly expected_actor="$2"
[[ -r "$manifest" ]] || { echo "not readable: $manifest" >&2; exit 2; }
jq -e . "$manifest" >/dev/null 2>&1 || { echo "not valid JSON: $manifest" >&2; exit 2; }
[[ -n "$expected_actor" ]] || { echo "EXPECTED_ACTOR must not be empty" >&2; exit 2; }

readonly repository="$(jq -r '.repository // empty' "$manifest")"
readonly pr_number="$(jq -r '.pr_number // empty' "$manifest")"
readonly head_sha="$(jq -r '.reviewed_head_sha // empty' "$manifest")"
readonly review_body="$(jq -r '.review_body // ""' "$manifest")"
readonly inline_comments="$(jq -c '.inline_comments // []' "$manifest")"
readonly replies="$(jq -c '.replies // []' "$manifest")"
readonly resolve_thread_ids="$(jq -c '.resolve_thread_ids // []' "$manifest")"
[[ "$repository" == */* ]] || { echo "manifest: repository must be OWNER/REPO" >&2; exit 2; }
[[ "$pr_number" =~ ^[1-9][0-9]*$ ]] || { echo "manifest: pr_number must be a positive integer" >&2; exit 2; }

readonly owner="${repository%%/*}"
readonly name="${repository##*/}"

unverified() { echo "published-unverified: $1" >&2; exit 1; }

reviews="$(gh api "repos/${repository}/pulls/${pr_number}/reviews" --paginate 2>/dev/null)" \
  || unverified "could not read the pull request reviews"
comments="$(gh api "repos/${repository}/pulls/${pr_number}/comments" --paginate 2>/dev/null)" \
  || unverified "could not read the pull request review comments"

# --- classify the actor's reviews on the reviewed head -------------------
# A review counts as REAL when it has a body or owns at least one INLINE
# finding. The qualifier matters: the reply that caused a shell lives inside
# that shell, so counting any owned comment would classify every shell as a
# real review and fail a correct publication. A reply is identified by
# `in_reply_to_id`; only a top-level comment is a finding.
classified="$(jq -c --arg actor "$expected_actor" --arg head "$head_sha" --argjson comments "$comments" '
  [ .[]
    | select(.user.login == $actor and .commit_id == $head)
    | . as $review
    | $review + {inline_count: ([$comments[]
        | select(.pull_request_review_id == $review.id and (.in_reply_to_id == null))] | length)} ]
  ' <<<"$reviews")" || unverified "could not classify the reviews"

readonly real_reviews="$(jq -c '[.[] | select((.body // "") != "" or .inline_count > 0)]' <<<"$classified")"
readonly shells="$(jq -c '[.[] | select((.body // "") == "" and .inline_count == 0)]' <<<"$classified")"
readonly real_count="$(jq 'length' <<<"$real_reviews")"
readonly shell_count="$(jq 'length' <<<"$shells")"
readonly reply_count="$(jq 'length' <<<"$replies")"
readonly inline_count="$(jq 'length' <<<"$inline_comments")"

echo "implicit reply shells: ${shell_count}"

# --- what the manifest asked for decides what must be there --------------
# The publisher's own predicate, recomputed from the manifest so the two cannot
# disagree: it submits a review when there is a body or an inline finding, and
# it batches the replies into that review whenever both are present.
publish_review=false
[[ -n "$review_body" || "$inline_count" -gt 0 ]] && publish_review=true

if [[ "$publish_review" == true ]]; then
  # A review was asked for, so exactly one must carry content on this head.
  [[ "$real_count" -ge 1 ]] \
    || unverified "no review by ${expected_actor} on ${head_sha}"
  [[ "$real_count" == 1 ]] \
    || unverified "unexpected additional review: ${real_count} reviews by ${expected_actor} carry content on ${head_sha}"

  # On the batched route the replies ride the submitted review, so the platform
  # creates no container and none is tolerated: a body-less review here is a
  # second event. With a review and no replies there is nothing a shell could be
  # explained by either, so both cases reduce to zero.
  [[ "$shell_count" == 0 ]] \
    || unverified "unexpected additional review: ${shell_count} body-less reviews on a route that carries its ${reply_count} replies inside the submitted review"

  published="$(jq -c '.[0]' <<<"$real_reviews")"
  [[ "$(jq -r '.state' <<<"$published")" == COMMENTED ]] \
    || unverified "review state is $(jq -r '.state' <<<"$published"), expected COMMENTED"

  if [[ -n "$review_body" ]]; then
    [[ "$(jq -r '.body // ""' <<<"$published")" == "$review_body" ]] \
      || unverified "the published review body differs from the manifest"
  else
    # No summary was submitted, so the inline findings are what prove the review
    # is the one the manifest describes.
    [[ "$(jq -r '.inline_count' <<<"$published")" -gt 0 ]] \
      || unverified "the review has neither a body nor inline findings"
  fi
else
  # Replies or resolutions only: the REST route, and the only one on which a
  # shell can legitimately appear. The pass submits no review of its own, so a
  # review carrying content on this head is an event nobody asked for. The
  # replies and resolutions below are still verified; only the review checks are
  # skipped, because the manifest asked for no review.
  [[ "$real_count" == 0 ]] \
    || unverified "unexpected additional review: ${real_count} reviews by ${expected_actor} carry content on ${head_sha} though the manifest requested none"
  [[ "$shell_count" -le "$reply_count" ]] \
    || unverified "unexpected additional review: ${shell_count} body-less reviews for ${reply_count} replies"
fi

# --- replies -------------------------------------------------------------
while IFS= read -r comment_id; do
  [[ -n "$comment_id" ]] || continue
  match="$(jq -c --argjson target "$comment_id" --arg actor "$expected_actor" \
    'first(.[] | select(.in_reply_to_id == $target and .user.login == $actor)) // empty' <<<"$comments")"
  [[ -n "$match" ]] \
    || unverified "no reply by ${expected_actor} to comment ${comment_id}"
done < <(jq -r '.[].comment_id' <<<"$replies")

# --- resolutions ---------------------------------------------------------
if [[ "$(jq 'length' <<<"$resolve_thread_ids")" -gt 0 ]]; then
  thread_state="$(
    cursor=""
    while :; do
      args=(-f query='query($owner: String!, $name: String!, $number: Int!, $after: String) { repository(owner: $owner, name: $name) { pullRequest(number: $number) { reviewThreads(first: 100, after: $after) { nodes { id isResolved } pageInfo { hasNextPage endCursor } } } } }' -f owner="$owner" -f name="$name" -F number="$pr_number")
      [[ -z "$cursor" ]] || args+=(-f after="$cursor")
      page="$(gh api graphql "${args[@]}")" || exit 1
      jq -r '.data.repository.pullRequest.reviewThreads.nodes[] | "\(.id) \(.isResolved)"' <<<"$page"
      [[ "$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage' <<<"$page")" == true ]] || break
      cursor="$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor' <<<"$page")"
    done
  )" || unverified "could not read the pull request review threads"
  while IFS= read -r thread_id; do
    [[ -n "$thread_id" ]] || continue
    state="$(awk -v want="$thread_id" '$1 == want { print $2; exit }' <<<"$thread_state")"
    [[ "$state" == true ]] \
      || unverified "thread ${thread_id} is not resolved"
  done < <(jq -r '.[]' <<<"$resolve_thread_ids")
fi

echo "published-ok"
