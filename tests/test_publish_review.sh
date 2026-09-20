#!/usr/bin/env bash
# Behavioral coverage for .github/scripts/publish-review.sh.
#
# Ported from a consumer project's deployment test suite as part of
# dr-agents#260 (T08). Those tests executed the vendored copy of this
# script and were, until this file existed, the only behavioral coverage of it
# anywhere. The script now lives here and is reached through the central
# reusable definition, so the coverage belongs here too: a consumer must not be
# the last place a publication guarantee is checked.
#
# The guarantees below all protect the same thing — that this publisher refuses
# to mutate GitHub when it cannot prove it is acting as the right App on the
# reviewed state. That is the dr-agents#258 failure class.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly script="$root/.github/scripts/publish-review.sh"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
mkdir -p "$temp/bin" "$temp/run"

readonly HEAD_SHA="$(printf 'a%.0s' {1..40})"
readonly OTHER_SHA="$(printf 'b%.0s' {1..40})"

# A single fake gh, driven by files the individual cases write. Every call is
# logged so a case can assert both what was requested and what was not.
cat >"$temp/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "$*" >>"${FAKE_GH_LOG:?}"
case "$1 $2" in
  'api repos/owner/repo/pulls/1')
    if [[ "$*" == *"--jq .head.sha"* ]]; then echo "${FAKE_HEAD_SHA:?}"; exit 0; fi ;;
esac
case "$*" in
  *'pulls/comments/'*'in_reply_to_id'*) printf '%s' "${FAKE_IN_REPLY_TO:-}"; exit 0 ;;
  *'pulls/comments/'*'pull_request_url'*) echo "${FAKE_COMMENT_PR_URL:?}"; exit 0 ;;
  *'resolveReviewThread'*) echo "${FAKE_RESOLVE_RESULT:-true}"; exit 0 ;;
  'api --method POST '*'/reviews'*) cat "${FAKE_REVIEW_RESULT:?}"; exit 0 ;;
  'api --method POST '*'/comments'*) cat "${FAKE_REPLY_RESULT:?}"; exit 0 ;;
esac
case "$*" in
  *'addPullRequestReviewThreadReply'*) cat "${FAKE_REPLY_MUTATION_RESULT:?}"; exit 0 ;;
  *'submitPullRequestReview'*) cat "${FAKE_SUBMIT_RESULT:?}"; exit 0 ;;
  *'pullRequest(number: $number) { id }'*) echo "${FAKE_PR_NODE_ID:-PR_node}"; exit 0 ;;
esac
if [[ "$*" == *'--input pending-review.json'* ]]; then cat "${FAKE_PENDING_RESULT:?}"; exit 0; fi
if [[ "$*" == *"reviews/${FAKE_SUBMITTED_ID:-9001}"* ]]; then cat "${FAKE_REVIEW_RESULT:?}"; exit 0; fi
if [[ "$1 $2 $3" == 'api graphql -f' ]]; then
  if [[ "$*" == *'after=cursor-one'* ]]; then cat "${FAKE_THREADS_PAGE2:?}"; else cat "${FAKE_THREADS_PAGE1:?}"; fi
  exit 0
fi
echo "unexpected-gh-call: $*" >&2
exit 99
EOF
chmod +x "$temp/bin/gh"
export PATH="$temp/bin:$PATH"

export GH_TOKEN=test GITHUB_REPOSITORY=owner/repo PR_NUMBER=1 REVIEW_EVENT=COMMENT
export FAKE_HEAD_SHA="$HEAD_SHA" FAKE_COMMENT_PR_URL="https://api.github.com/repos/owner/repo/pulls/1"

reset_case() {
  : >"$temp/log"
  export FAKE_GH_LOG="$temp/log"
  export REVIEWED_HEAD_SHA="$HEAD_SHA" EXPECTED_AUTHOR='cody-dr[bot]' PUBLISHER_APP_SLUG='cody-dr'
  export FAKE_HEAD_SHA="$HEAD_SHA" FAKE_IN_REPLY_TO="" FAKE_RESOLVE_RESULT=true
  export FAKE_COMMENT_PR_URL="https://api.github.com/repos/owner/repo/pulls/1"
  unset REVIEW_BODY INLINE_COMMENTS_JSON REPLIES_JSON RESOLVE_THREAD_IDS_JSON 2>/dev/null || true
  echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}' >"$temp/p1"
  echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}' >"$temp/p2"
  export FAKE_THREADS_PAGE1="$temp/p1" FAKE_THREADS_PAGE2="$temp/p2"
  jq -n '{user:{login:"cody-dr[bot]"},pull_request_url:"https://api.github.com/repos/owner/repo/pulls/1",state:"COMMENTED"}' >"$temp/review-result"
  jq -n '{user:{login:"cody-dr[bot]"}}' >"$temp/reply-result"
  export FAKE_REVIEW_RESULT="$temp/review-result" FAKE_REPLY_RESULT="$temp/reply-result"
  jq -n '{data:{addPullRequestReview:{pullRequestReview:{id:"PRR_pending"}}}}' >"$temp/pending-result"
  jq -n '{data:{addPullRequestReviewThreadReply:{comment:{databaseId:5001}}}}' >"$temp/reply-mutation"
  jq -n '{data:{submitPullRequestReview:{pullRequestReview:{databaseId:9001,state:"COMMENTED"}}}}' >"$temp/submit-result"
  export FAKE_PENDING_RESULT="$temp/pending-result" FAKE_REPLY_MUTATION_RESULT="$temp/reply-mutation"
  export FAKE_SUBMIT_RESULT="$temp/submit-result" FAKE_SUBMITTED_ID=9001 FAKE_PR_NODE_ID=PR_node
}

# Runs the script in its own directory: it writes review.json into the CWD.
run_script() { ( cd "$temp/run" && bash "$script" ) >"$temp/out" 2>"$temp/err"; }

expect_fail_with() {
  local message="$1"
  if run_script; then echo "FAIL: expected a non-zero exit for: ${message}" >&2; exit 1; fi
  grep -q "$message" "$temp/err" || {
    echo "FAIL: expected stderr to mention '${message}'" >&2; cat "$temp/err" >&2; exit 1; }
}

# --- refuses to act as the wrong App, before touching GitHub ---------------
reset_case
export PUBLISHER_APP_SLUG=wrong-app REVIEW_BODY=summary
expect_fail_with "unexpected authenticated app"
[[ ! -s "$temp/log" ]] || { echo "FAIL: wrong App must be rejected before any gh call" >&2; cat "$temp/log" >&2; exit 1; }
echo "ok: refuses a mismatched App before any GitHub call"

# --- refuses when the PR head moved since the review -----------------------
reset_case
export REVIEW_BODY=summary FAKE_HEAD_SHA="$OTHER_SHA"
expect_fail_with "PR head changed since review"
grep -q -- "--method POST" "$temp/log" && { echo "FAIL: mutated after a head change" >&2; exit 1; }
echo "ok: refuses a stale head before mutating"

# --- paginates thread validation, then resolves ----------------------------
reset_case
export RESOLVE_THREAD_IDS_JSON='["thread-two"]'
echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"id":"thread-one"}],"pageInfo":{"hasNextPage":true,"endCursor":"cursor-one"}}}}}}' >"$temp/p1"
echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"id":"thread-two"}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}' >"$temp/p2"
run_script || { echo "FAIL: pagination case should succeed" >&2; cat "$temp/err" >&2; exit 1; }
grep -q "after=cursor-one" "$temp/log" || { echo "FAIL: did not request the second page" >&2; exit 1; }
grep -q "resolveReviewThread" "$temp/log" || { echo "FAIL: did not resolve the thread found on page two" >&2; exit 1; }
echo "ok: follows every page before resolving a thread"

# --- refuses a thread that is absent from all pages ------------------------
reset_case
export RESOLVE_THREAD_IDS_JSON='["missing-thread"]'
expect_fail_with "resolution target mismatch"
grep -q "resolveReviewThread" "$temp/log" && { echo "FAIL: resolved a thread it never found" >&2; exit 1; }
echo "ok: refuses to resolve a thread absent from every page"

# --- refuses a reply aimed at another pull request -------------------------
reset_case
export REPLIES_JSON='[{"comment_id":5,"body":"reply"}]'
export FAKE_COMMENT_PR_URL="https://api.github.com/repos/owner/repo/pulls/999"
expect_fail_with "reply target mismatch"
grep -q -- "--method POST" "$temp/log" && { echo "FAIL: replied to a comment on another PR" >&2; exit 1; }
echo "ok: refuses a reply targeting another pull request"

# --- refuses a reply aimed at a nested comment -----------------------------
reset_case
export REPLIES_JSON='[{"comment_id":5,"body":"reply"}]' FAKE_IN_REPLY_TO=42
expect_fail_with "reply target must be a top-level review comment"
echo "ok: refuses a reply targeting a nested comment"

# --- happy path: publishes, verifies authorship, reports -------------------
reset_case
export REVIEW_BODY=summary
run_script || { echo "FAIL: happy path should succeed" >&2; cat "$temp/err" >&2; exit 1; }
grep -q "Publication report:" "$temp/out" || { echo "FAIL: no publication report" >&2; exit 1; }
grep -q -- "--method POST repos/owner/repo/pulls/1/reviews" "$temp/log" || { echo "FAIL: no review was posted" >&2; exit 1; }
echo "ok: publishes a review and reports the outcome"

# --- rejects a review created by an unexpected author ----------------------
reset_case
export REVIEW_BODY=summary
jq -n '{user:{login:"someone-else"},pull_request_url:"https://api.github.com/repos/owner/repo/pulls/1",state:"COMMENTED"}' >"$temp/review-result"
expect_fail_with "unexpected review author"
echo "ok: rejects a review created by an unexpected author"

# --- a pass carrying both a review and replies emits no shell --------------
# dr-agents#380. The REST reply route creates an implicit empty review per
# reply; batching them into the submitted review is what removes the shells.
reset_case
export REVIEW_BODY=summary REPLIES_JSON='[{"comment_id":4242,"body":"verified"}]'
echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"id":"thread-one","comments":{"nodes":[{"databaseId":4242}]}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}' >"$temp/p1"
run_script || { echo "FAIL: batched case should succeed" >&2; cat "$temp/err" >&2; exit 1; }
grep -q "addPullRequestReviewThreadReply" "$temp/log" || { echo "FAIL: reply did not go through the batched mutation" >&2; cat "$temp/log" >&2; exit 1; }
grep -q "submitPullRequestReview" "$temp/log" || { echo "FAIL: the pending review was never submitted" >&2; exit 1; }
grep -q -- "--method POST repos/owner/repo/pulls/1/comments" "$temp/log" && { echo "FAIL: a REST reply was posted, which emits a shell" >&2; exit 1; }
grep -q -- "--method POST repos/owner/repo/pulls/1/reviews" "$temp/log" && { echo "FAIL: the REST review route ran alongside the batched one" >&2; exit 1; }
echo "ok: a review with replies is published as one batched review"

# --- replies with no review keep the REST route and state the limitation ---
reset_case
export REPLIES_JSON='[{"comment_id":4242,"body":"verified"}]'
run_script || { echo "FAIL: reply-only case should succeed" >&2; cat "$temp/err" >&2; exit 1; }
grep -q -- "--method POST repos/owner/repo/pulls/1/comments" "$temp/log" || { echo "FAIL: reply-only must use the REST route" >&2; exit 1; }
grep -q "submitPullRequestReview" "$temp/log" && { echo "FAIL: reply-only must not open a review" >&2; exit 1; }
echo "ok: a reply with no review keeps the REST route"

# --- a reply whose thread cannot be found fails before any mutation --------
reset_case
export REVIEW_BODY=summary REPLIES_JSON='[{"comment_id":4242,"body":"verified"}]'
echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"id":"thread-one","comments":{"nodes":[{"databaseId":777}]}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}' >"$temp/p1"
expect_fail_with "reply target has no review thread"
grep -q "addPullRequestReview(" "$temp/log" && { echo "FAIL: opened a pending review before proving the reply could land" >&2; exit 1; }
echo "ok: an unmappable reply fails while not-published is still honest"

echo "publish review tests passed"
