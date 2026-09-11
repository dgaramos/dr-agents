#!/usr/bin/env bash
# The typed publication outcome, across all five script-backed publishers.
#
# `reusable-publish-issue.yml` has emitted `not-published`,
# `published-unverified` and `published-ok` since the migration. The five
# publishers backed by scripts in this directory emitted nothing at all, which
# is the gap dr-agents#270 recorded and this file closes.
#
# The existing per-script tests assert behavior and are deliberately left
# untouched: they staying green is the evidence that this change adds signal
# without altering what any publisher does.
#
# The contract under test, taken from the issue publisher:
#   not-published        only before any mutation was attempted -- the only
#                        outcome that entitles the reader to republish
#   published-unverified a resource exists but verification failed; the text
#                        must tell the reader NOT to republish (the #258 shape)
#   published-ok         the happy path
# and, in every published case, the resource identifier is emitted BEFORE the
# verdict, so a red job is never read as "nothing was published".
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
mkdir -p "$temp/bin"
cd "$temp"

cat >"$temp/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >>"$TEST_LOG"
args="$*"
case "$args" in
  *"--method GET"*/pulls*)        echo "${EXISTING_PULLS:-[]}" ;;
  *"--method POST"*/pulls" --input"*) cat >/dev/null; cat "$RESULT" ;;
  "api repos/octo/example/pulls/12") cat "$RESULT" ;;
  *reviews" --input"*)            cat "$RESULT" ;;
  *graphql*query=query*)          cat "$THREADS" ;;
  *graphql*addPullRequestReviewThreadReply*) cat "$RESULT" ;;
  *graphql*resolveReviewThread*)  echo "${RESOLVE_RESULT:-true}" ;;
  *) echo "unstubbed gh call: $args" >&2; exit 1 ;;
esac
EOF
chmod +x "$temp/bin/gh"
export PATH="$temp/bin:$PATH"
export TEST_LOG="$temp/log" RESULT="$temp/result" THREADS="$temp/threads"
export GH_TOKEN=stub GITHUB_REPOSITORY=octo/example
export EXPECTED_AUTHOR='claudio-dr[bot]' PUBLISHER_APP_SLUG='claudio-dr'

failures=0
summary_file=""

begin() {
  summary_file="$temp/summary.$RANDOM"
  : >"$summary_file"
  : >"$TEST_LOG"
  export GITHUB_STEP_SUMMARY="$summary_file"
}

# assert_outcome <label> <expected outcome> <expected exit: ok|fail> <command...>
assert_outcome() {
  local label="$1" expected="$2" expect_exit="$3"; shift 3
  local status=0
  "$@" >"$temp/out" 2>&1 || status=$?
  if [[ "$expect_exit" == ok && "$status" != 0 ]]; then
    echo "FAIL ${label}: expected success, exited ${status}" >&2
    cat "$temp/out" >&2; failures=$((failures + 1)); return
  fi
  if [[ "$expect_exit" == fail && "$status" == 0 ]]; then
    echo "FAIL ${label}: expected a non-zero exit" >&2
    cat "$temp/out" >&2; failures=$((failures + 1)); return
  fi
  if ! grep -q "outcome: \`${expected}\`" "$summary_file"; then
    echo "FAIL ${label}: step summary does not report outcome '${expected}'" >&2
    echo "--- summary:" >&2; cat "$summary_file" >&2
    echo "--- output:" >&2; cat "$temp/out" >&2
    failures=$((failures + 1)); return
  fi
  # No outcome may be reported twice, and the three are mutually exclusive.
  local other
  for other in not-published published-unverified published-ok; do
    [[ "$other" == "$expected" ]] && continue
    if grep -q "outcome: \`${other}\`" "$summary_file"; then
      echo "FAIL ${label}: reported '${other}' alongside '${expected}'" >&2
      failures=$((failures + 1)); return
    fi
  done
  echo "ok ${label}: ${expected}"
}

# A published outcome must name the resource, and must do so before the
# verdict: that ordering is what stops a red job from reading as "nothing was
# published".
assert_resource_precedes_verdict() {
  local label="$1"
  local res_line ver_line
  res_line="$(grep -n 'resource:' "$summary_file" | head -1 | cut -d: -f1)"
  ver_line="$(grep -n 'outcome:' "$summary_file" | head -1 | cut -d: -f1)"
  if [[ -z "$res_line" ]]; then
    echo "FAIL ${label}: a published outcome must name the resource" >&2
    cat "$summary_file" >&2; failures=$((failures + 1)); return
  fi
  if (( res_line > ver_line )); then
    echo "FAIL ${label}: the resource must be named before the verdict" >&2
    cat "$summary_file" >&2; failures=$((failures + 1)); return
  fi
  echo "ok ${label}: resource named before the verdict"
}

assert_says_do_not_republish() {
  local label="$1"
  if ! grep -qi 'not republish\|do not republish' "$summary_file"; then
    echo "FAIL ${label}: published-unverified must tell the reader not to republish" >&2
    cat "$summary_file" >&2; failures=$((failures + 1)); return
  fi
  echo "ok ${label}: says do not republish"
}

pr_json() {
  jq -n --arg actor "$1" '{number:12, user:{login:$actor}, title:"t", body:"b",
    head:{ref:"feature", repo:{full_name:"octo/example"}},
    base:{ref:"main", repo:{full_name:"octo/example"}},
    html_url:"https://github.com/octo/example/pull/12"}'
}

# ---------------------------------------------------------------- publish-pr
export TITLE=t BODY=b HEAD_BRANCH=feature BASE_BRANCH=main
readonly pr=".github/scripts/publish-pr.sh"

begin; pr_json 'claudio-dr[bot]' >"$RESULT"
assert_outcome "publish-pr happy" published-ok ok bash "$root/$pr"
assert_resource_precedes_verdict "publish-pr happy"

# Pre-mutation refusal: nothing was created, so republishing is safe.
begin; pr_json 'claudio-dr[bot]' >"$RESULT"
assert_outcome "publish-pr wrong app" not-published fail \
  env PUBLISHER_APP_SLUG=wrong bash "$root/$pr"
if grep -q 'POST' "$TEST_LOG"; then
  echo "FAIL publish-pr wrong app: not-published was reported after a mutation" >&2
  failures=$((failures + 1))
fi

# The #258 shape: the pull request was created, then verification failed.
begin; pr_json 'someone-else' >"$RESULT"
assert_outcome "publish-pr unverified" published-unverified fail bash "$root/$pr"
assert_resource_precedes_verdict "publish-pr unverified"
assert_says_do_not_republish "publish-pr unverified"

# ------------------------------------------------------- thread action: reply
for adapter in claudio cody; do
  script=".github/scripts/publish-${adapter}-thread-action.sh"
  export EXPECTED_AUTHOR="${adapter}-dr[bot]" PUBLISHER_APP_SLUG="${adapter}-dr"
  export PR_NUMBER=12 THREAD_ID=thread-one BODY=b THREAD_ACTION=reply
  jq -n '{data:{repository:{pullRequest:{reviewThreads:{nodes:[{id:"thread-one"}],
    pageInfo:{hasNextPage:false, endCursor:null}}}}}}' >"$THREADS"

  begin
  jq -n --arg actor "${adapter}-dr" '{data:{addPullRequestReviewThreadReply:{comment:{
    author:{login:$actor}, pullRequest:{number:12, repository:{nameWithOwner:"octo/example"}}}}}}' >"$RESULT"
  assert_outcome "${adapter} reply happy" published-ok ok bash "$root/$script"
  assert_resource_precedes_verdict "${adapter} reply happy"

  # Thread not on this pull request: refused before the mutation.
  begin
  jq -n '{data:{repository:{pullRequest:{reviewThreads:{nodes:[{id:"other"}],
    pageInfo:{hasNextPage:false, endCursor:null}}}}}}' >"$THREADS"
  assert_outcome "${adapter} reply wrong thread" not-published fail bash "$root/$script"
  jq -n '{data:{repository:{pullRequest:{reviewThreads:{nodes:[{id:"thread-one"}],
    pageInfo:{hasNextPage:false, endCursor:null}}}}}}' >"$THREADS"

  # The literal #258 defect: the comment posted, the author check then failed.
  begin
  jq -n '{data:{addPullRequestReviewThreadReply:{comment:{
    author:{login:"someone-else"}, pullRequest:{number:12, repository:{nameWithOwner:"octo/example"}}}}}}' >"$RESULT"
  assert_outcome "${adapter} reply unverified" published-unverified fail bash "$root/$script"
  assert_says_do_not_republish "${adapter} reply unverified"

  # Resolve is a mutation too, and a false result is a post-mutation failure.
  begin
  THREAD_ACTION=resolve RESOLVE_RESULT=false assert_outcome \
    "${adapter} resolve unverified" published-unverified fail bash "$root/$script"
  begin
  assert_outcome "${adapter} resolve happy" published-ok ok \
    env THREAD_ACTION=resolve bash "$root/$script"
done
unset PR_NUMBER THREAD_ID THREAD_ACTION
export EXPECTED_AUTHOR='claudio-dr[bot]' PUBLISHER_APP_SLUG='claudio-dr'

# ------------------------------------------------------------ publish-review
readonly review=".github/scripts/publish-review.sh"
export PR_NUMBER=12 REVIEW_EVENT=COMMENT REVIEW_BODY=summary
export REVIEWED_HEAD_SHA=0123456789012345678901234567890123456789
export INLINE_COMMENTS_JSON='[]' REPLIES_JSON='[]' RESOLVE_THREAD_IDS_JSON='[]'

cat >"$temp/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >>"$TEST_LOG"
case "$*" in
  'api repos/octo/example/pulls/12 --jq .head.sha') echo "$REVIEWED_HEAD_SHA" ;;
  'api --method POST repos/octo/example/pulls/12/reviews --input review.json') cat "$RESULT" ;;
  *) echo "unstubbed gh call: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$temp/bin/gh"

begin
jq -n '{user:{login:"claudio-dr[bot]"}, id:99, state:"COMMENTED",
  pull_request_url:"https://api.github.com/repos/octo/example/pulls/12",
  html_url:"https://github.com/octo/example/pull/12#pullrequestreview-99"}' >"$RESULT"
assert_outcome "publish-review happy" published-ok ok bash "$root/$review"
assert_resource_precedes_verdict "publish-review happy"

begin
assert_outcome "publish-review wrong app" not-published fail \
  env PUBLISHER_APP_SLUG=wrong bash "$root/$review"

begin
jq -n '{user:{login:"someone-else"}, id:99, state:"COMMENTED",
  pull_request_url:"https://api.github.com/repos/octo/example/pulls/12",
  html_url:"https://github.com/octo/example/pull/12#pullrequestreview-99"}' >"$RESULT"
assert_outcome "publish-review unverified" published-unverified fail bash "$root/$review"
assert_says_do_not_republish "publish-review unverified"

# ------------------------------------------------------- publish-pr-metadata
readonly metadata=".github/scripts/publish-pr-metadata.sh"
export BASE_BRANCH=main LABELS_JSON='["x"]' ASSIGNEES_JSON='[]' REVIEWERS_JSON='[]'
printf '#!/usr/bin/env bash\nexit 0\n' >"$temp/helper-ok.sh"
printf '#!/usr/bin/env bash\nexit 1\n' >"$temp/helper-fail.sh"
chmod +x "$temp/helper-ok.sh" "$temp/helper-fail.sh"

begin
assert_outcome "publish-pr-metadata happy" published-ok ok \
  env METADATA_HELPER="$temp/helper-ok.sh" bash "$root/$metadata"
assert_resource_precedes_verdict "publish-pr-metadata happy"

begin
assert_outcome "publish-pr-metadata wrong app" not-published fail \
  env PUBLISHER_APP_SLUG=wrong METADATA_HELPER="$temp/helper-ok.sh" bash "$root/$metadata"

# The helper mutates as it goes, so a failure can leave metadata half applied.
# That is not `not-published`.
begin
assert_outcome "publish-pr-metadata unverified" published-unverified fail \
  env METADATA_HELPER="$temp/helper-fail.sh" bash "$root/$metadata"
assert_says_do_not_republish "publish-pr-metadata unverified"

if (( failures > 0 )); then
  echo "${failures} outcome assertion(s) failed" >&2
  exit 1
fi
echo "publication outcome tests passed"
