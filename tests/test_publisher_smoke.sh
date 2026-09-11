#!/usr/bin/env bash
# Coverage for the real-dispatch smoke test helpers (dr-agents#267).
#
# The smoke test itself can only be validated by a real dispatch. What *can* be
# tested here is the part that decides whether a dispatch passed, and the part
# that removes what a dispatch left behind. Both are pure functions of GitHub's
# responses, so a stubbed `gh` exercises them completely.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
mkdir -p "$temp/bin"

# A stub `gh` that answers from fixture files. Each fixture is keyed by the
# request, so a test declares only the responses it cares about.
cat >"$temp/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >>"$TEST_LOG"
key="$(printf '%s' "$*" | tr -c 'A-Za-z0-9' '_')"
# Real `gh` newline-terminates its output; a fixture read by a `while read`
# loop is dropped without it.
if [[ -f "$FIXTURES/$key" ]]; then cat "$FIXTURES/$key"; echo; exit 0; fi
if [[ -f "$FIXTURES/$key.fail" ]]; then cat "$FIXTURES/$key.fail" >&2; exit 1; fi
echo "unstubbed gh call: $*" >&2
exit 1
EOF
chmod +x "$temp/bin/gh"
export PATH="$temp/bin:$PATH"
export TEST_LOG="$temp/log" FIXTURES="$temp/fixtures"
export GH_TOKEN=stub GITHUB_REPOSITORY=octo/example
export GITHUB_STEP_SUMMARY="$temp/summary"

stub() {
  # stub <gh argument string> <response body>
  mkdir -p "$FIXTURES"
  printf '%s' "$2" >"$FIXTURES/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_')"
}
stub_failure() {
  mkdir -p "$FIXTURES"
  printf '%s' "$2" >"$FIXTURES/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_').fail"
}
reset() {
  rm -rf "$FIXTURES" "$TEST_LOG" "$GITHUB_STEP_SUMMARY"
  mkdir -p "$FIXTURES"
  : >"$TEST_LOG"
  : >"$GITHUB_STEP_SUMMARY"
}

readonly assert_script="$root/.github/scripts/smoke-publishers-assert.sh"
readonly reap_script="$root/.github/scripts/smoke-publishers-reap.sh"

# Every publisher resource the smoke chain produces, answering as the App.
stub_all_green() {
  stub 'api repos/octo/example/issues/7 --jq .user.login' 'claudio-dr[bot]'
  stub 'api repos/octo/example/pulls/12 --jq .user.login' 'claudio-dr[bot]'
  stub 'api repos/octo/example/issues/12 --jq [.labels[].name]' '["smoke"]'
  stub 'api repos/octo/example/pulls/12/reviews --jq .[-1].user.login' 'claudio-dr[bot]'
  stub 'api repos/octo/example/pulls/12/comments --jq .[-1].user.login' 'claudio-dr[bot]'
  stub 'api graphql -f query=THREAD_RESOLVED -f thread=THREAD_1 --jq .data.node.isResolved' 'true'
}

export EXPECTED_AUTHOR='claudio-dr[bot]'
# Substitute a short token for the real GraphQL query, so the stub above can be
# keyed on a readable argument string.
export SMOKE_THREAD_QUERY=THREAD_RESOLVED

readonly all_green_checks='[
  {"publisher":"issue","kind":"issue","ref":"7","job_result":"success"},
  {"publisher":"pr","kind":"pr","ref":"12","job_result":"success"},
  {"publisher":"pr-metadata","kind":"pr-labels","ref":"12","expect":"smoke","job_result":"success"},
  {"publisher":"review","kind":"review","ref":"12","job_result":"success"},
  {"publisher":"reply","kind":"reply","ref":"12","job_result":"success"},
  {"publisher":"resolve","kind":"resolve","ref":"THREAD_1","expect":"true","job_result":"success"}
]'

# --- Happy path -------------------------------------------------------------
# All six publishers produced their resource, each authored by the App, and
# every job concluded success.
reset
stub_all_green
if ! CHECKS_JSON="$all_green_checks" bash "$assert_script" >"$temp/out" 2>&1; then
  echo "FAIL: a fully green dispatch must pass" >&2
  cat "$temp/out" >&2
  exit 1
fi
for publisher in issue pr pr-metadata review reply resolve; do
  grep -q "$publisher" "$GITHUB_STEP_SUMMARY" || {
    echo "FAIL: $publisher missing from the run summary" >&2; exit 1; }
done

# --- Failure path: the #258 shape -------------------------------------------
# THE most important case in this file. In dr-agents#258 the reply publisher
# posted the comment and *then* exited 1, because it compared a suffixless
# GraphQL login against a REST-form EXPECTED_AUTHOR. The resource was published
# and the job was red. An assertion that trusts the exit code alone reports a
# clean failure; an assertion that trusts the resource alone reports a pass.
# Neither is right: the run must fail, and it must fail *naming* the publisher
# whose resource exists over a red job, because that is the state a human has
# to go clean up by hand.
reset
stub_all_green
published_but_red="$(jq -c '(.[] | select(.publisher == "reply") | .job_result) = "failure"' <<<"$all_green_checks")"
if CHECKS_JSON="$published_but_red" bash "$assert_script" >"$temp/out" 2>&1; then
  echo "FAIL: a published resource over a red job must not pass" >&2
  exit 1
fi
grep -q 'reply' "$temp/out" || {
  echo "FAIL: the failing publisher must be identifiable from the output" >&2
  cat "$temp/out" >&2; exit 1; }
grep -qi 'published' "$temp/out" || {
  echo "FAIL: output must say the resource was published despite the red job" >&2
  cat "$temp/out" >&2; exit 1; }

# --- Failure path: wrong author ---------------------------------------------
# A green job that published under the wrong identity is still a failure.
reset
stub_all_green
stub 'api repos/octo/example/pulls/12 --jq .user.login' 'dgaramos'
if CHECKS_JSON="$all_green_checks" bash "$assert_script" >"$temp/out" 2>&1; then
  echo "FAIL: a resource authored by a non-App identity must not pass" >&2
  exit 1
fi
grep -q 'dgaramos' "$temp/out" || {
  echo "FAIL: the observed author must appear in the output" >&2
  cat "$temp/out" >&2; exit 1; }

# --- Failure path: nothing published at all ---------------------------------
# The METADATA_HELPER and ref-skew shapes: the publisher resolved no file and
# died before mutating anything. No resource exists and the job is red.
reset
stub_all_green
stub_failure 'api repos/octo/example/pulls/12 --jq .user.login' 'gh: Not Found (HTTP 404)'
nothing_published="$(jq -c '(.[] | select(.publisher == "pr") | .job_result) = "failure"' <<<"$all_green_checks")"
if CHECKS_JSON="$nothing_published" bash "$assert_script" >"$temp/out" 2>&1; then
  echo "FAIL: a publisher that produced no resource must not pass" >&2
  exit 1
fi
grep -q 'pr' "$temp/out" || {
  echo "FAIL: the failing publisher must be identifiable from the output" >&2
  cat "$temp/out" >&2; exit 1; }

# --- Edge case: a cancelled job is not a pass -------------------------------
reset
stub_all_green
cancelled="$(jq -c '(.[] | select(.publisher == "resolve") | .job_result) = "cancelled"' <<<"$all_green_checks")"
if CHECKS_JSON="$cancelled" bash "$assert_script" >"$temp/out" 2>&1; then
  echo "FAIL: a cancelled publisher job must not pass" >&2
  exit 1
fi

# --- Reaper: happy path -----------------------------------------------------
# A stale pull request and its branch are both removed.
reset
stub 'api repos/octo/example/pulls --paginate --jq .[] | select(.head.ref | startswith("smoke/publishers-")) | [.number, .head.ref, .created_at] | @tsv' \
  '4	smoke/publishers-111	2000-01-01T00:00:00Z'
stub 'api repos/octo/example/git/matching-refs/heads/smoke/publishers- --paginate --jq .[].ref' \
  'refs/heads/smoke/publishers-111'
stub 'api --method PATCH repos/octo/example/pulls/4 -f state=closed' '{}'
stub 'api --method DELETE repos/octo/example/git/refs/heads/smoke/publishers-111' ''
SMOKE_MAX_AGE_SECONDS=1 bash "$reap_script" >"$temp/out" 2>&1 || {
  echo "FAIL: the reaper must succeed on a clean sweep" >&2; cat "$temp/out" >&2; exit 1; }
grep -q 'DELETE repos/octo/example/git/refs/heads/smoke/publishers-111' "$TEST_LOG" || {
  echo "FAIL: a stale branch must be deleted" >&2; cat "$TEST_LOG" >&2; exit 1; }
grep -q 'PATCH repos/octo/example/pulls/4' "$TEST_LOG" || {
  echo "FAIL: a stale pull request must be closed" >&2; cat "$TEST_LOG" >&2; exit 1; }

# --- Reaper edge case: a branch with no pull request ------------------------
# The run died between pushing the branch and creating the PR. The branch is
# still litter and must still be swept.
reset
stub 'api repos/octo/example/pulls --paginate --jq .[] | select(.head.ref | startswith("smoke/publishers-")) | [.number, .head.ref, .created_at] | @tsv' ''
stub 'api repos/octo/example/git/matching-refs/heads/smoke/publishers- --paginate --jq .[].ref' \
  'refs/heads/smoke/publishers-222'
stub 'api --method DELETE repos/octo/example/git/refs/heads/smoke/publishers-222' ''
SMOKE_MAX_AGE_SECONDS=1 bash "$reap_script" >"$temp/out" 2>&1 || {
  echo "FAIL: an orphaned branch must be swept" >&2; cat "$temp/out" >&2; exit 1; }
grep -q 'DELETE repos/octo/example/git/refs/heads/smoke/publishers-222' "$TEST_LOG" || {
  echo "FAIL: a branch with no pull request must be deleted" >&2; cat "$TEST_LOG" >&2; exit 1; }

# --- Reaper edge case: the current run's branch is spared -------------------
reset
stub 'api repos/octo/example/pulls --paginate --jq .[] | select(.head.ref | startswith("smoke/publishers-")) | [.number, .head.ref, .created_at] | @tsv' ''
stub 'api repos/octo/example/git/matching-refs/heads/smoke/publishers- --paginate --jq .[].ref' \
  'refs/heads/smoke/publishers-333'
SMOKE_KEEP_BRANCH=smoke/publishers-333 SMOKE_MAX_AGE_SECONDS=1 bash "$reap_script" >"$temp/out" 2>&1 || {
  echo "FAIL: sparing the current branch must not fail the reaper" >&2; cat "$temp/out" >&2; exit 1; }
if grep -q 'DELETE' "$TEST_LOG"; then
  echo "FAIL: the current run's own branch must not be deleted" >&2
  cat "$TEST_LOG" >&2; exit 1
fi

# --- Reaper edge case: an unremovable resource is named, not fatal ----------
# AC-04: what the reaper cannot remove must be named in the run output. It must
# not redden the run on its own, or a protected leftover would mask the result
# of the dispatch the run exists to measure.
reset
stub 'api repos/octo/example/pulls --paginate --jq .[] | select(.head.ref | startswith("smoke/publishers-")) | [.number, .head.ref, .created_at] | @tsv' ''
stub 'api repos/octo/example/git/matching-refs/heads/smoke/publishers- --paginate --jq .[].ref' \
  'refs/heads/smoke/publishers-444'
stub_failure 'api --method DELETE repos/octo/example/git/refs/heads/smoke/publishers-444' \
  'gh: Reference protected (HTTP 422)'
SMOKE_MAX_AGE_SECONDS=1 bash "$reap_script" >"$temp/out" 2>&1 || {
  echo "FAIL: an unremovable leftover must not fail the reaper" >&2; cat "$temp/out" >&2; exit 1; }
grep -q 'smoke/publishers-444' "$temp/out" || {
  echo "FAIL: an unremovable resource must be named in the output" >&2
  cat "$temp/out" >&2; exit 1; }
grep -q 'smoke/publishers-444' "$GITHUB_STEP_SUMMARY" || {
  echo "FAIL: an unremovable resource must be named in the step summary" >&2
  cat "$GITHUB_STEP_SUMMARY" >&2; exit 1; }

echo "publisher smoke tests passed"
