#!/usr/bin/env bash
# Drive core/pr-review/scripts/verify-review-surface.sh against real and
# deliberately broken copies of the review surface files.
#
# The script is exercised directly rather than through bin/check, because
# bin/check calls this test: a test that re-entered bin/check would recurse.
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

readonly verifier="core/pr-review/scripts/verify-review-surface.sh"
readonly contract="core/pr-review/references/review-contract.md"
readonly reporting="core/pr-review/references/reporting.md"
readonly example="examples/generic-pr-review.md"

temporary_root="$(mktemp -d)"
trap 'rm -rf "$temporary_root"' EXIT

failures=0

pass() { echo "ok: $1"; }
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

# Build an isolated fixture set that a case may mutate freely.
make_fixture() {
  local name="$1"
  local dir="$temporary_root/$name"
  mkdir -p "$dir"
  cp "$contract" "$dir/review-contract.md"
  cp "$reporting" "$dir/reporting.md"
  cp "$example" "$dir/generic-pr-review.md"
  echo "$dir"
}

run_verifier() {
  local dir="$1"
  bash "$verifier" \
    "$dir/review-contract.md" "$dir/reporting.md" "$dir/generic-pr-review.md" 2>&1
}

# --- happy path: the shipped files satisfy the unified surface --------------
if output="$(run_verifier "$(make_fixture happy)")"; then
  pass "A: the shipped review surface passes the verifier"
else
  fail "A: the shipped review surface was rejected: $output"
fi

# --- failure path: a template anchor changed in only one file ---------------
divergent="$(make_fixture divergent)"
# Rename a class badge in reporting.md only. review-contract.md still carries
# the original, so the two files no longer agree on the anchor set.
sed -i.bak 's/🟡 Minor/🟢 Trivial/' "$divergent/reporting.md"
if output="$(run_verifier "$divergent")"; then
  fail "B: a one-sided class-badge change was accepted"
elif grep -qi 'diverge' <<<"$output"; then
  pass "B: a one-sided class-badge change fails naming the divergence"
else
  fail "B: rejected without naming the divergence: $output"
fi

# --- failure path: a one-sided category change -----------------------------
category="$(make_fixture category)"
sed -i.bak 's/Performance & capacity/Performance \& throughput/' \
  "$category/reporting.md"
if output="$(run_verifier "$category")"; then
  fail "B2: a one-sided category change was accepted"
elif grep -qi 'diverge' <<<"$output"; then
  pass "B2: a one-sided category change fails naming the divergence"
else
  fail "B2: rejected without naming the divergence: $output"
fi

# --- failure path: Publication: back in the published body -----------------
publication="$(make_fixture publication)"
# Re-insert the removed field into the summary template's field run.
awk '
  /^\*\*Verdict:\*\*/ {
    print
    print "**Publication:** `<not requested|not published|published by <reviewer name>>`"
    next
  }
  { print }
' "$publication/review-contract.md" >"$publication/patched" &&
  mv "$publication/patched" "$publication/review-contract.md"
if output="$(run_verifier "$publication")"; then
  fail "C: a Publication field in the published body was accepted"
elif grep -qi 'publication' <<<"$output"; then
  pass "C: a Publication field in the published body is rejected"
else
  fail "C: rejected without naming the publication field: $output"
fi

# --- failure path: Publication: back in the example ------------------------
example_case="$(make_fixture example)"
printf '\nThe summary records `Publication: not requested`.\n' \
  >>"$example_case/generic-pr-review.md"
if output="$(run_verifier "$example_case")"; then
  fail "C2: a Publication string in the example was accepted"
elif grep -qi 'publication' <<<"$output"; then
  pass "C2: a Publication string in the example is rejected"
else
  fail "C2: rejected without naming the publication field: $output"
fi

# --- edge case: Publication in prose outside the published-body field run ---
prose="$(make_fixture prose)"
printf '\nThe terminal summary and the manifest still carry the publication\n' \
  >>"$prose/review-contract.md"
printf 'status; the words Publication: published appear only there.\n' \
  >>"$prose/review-contract.md"
if output="$(run_verifier "$prose")"; then
  pass "D: Publication in prose outside the published body is allowed"
else
  fail "D: prose mentioning publication status was rejected: $output"
fi

# --- failure path: reporting.md re-defining the finding template ------------
duplicate="$(make_fixture duplicate)"
printf '\n**Evidence:** `<file:line>` — <verified fact>; confidence: <N>/100.\n' \
  >>"$duplicate/reporting.md"
if output="$(run_verifier "$duplicate")"; then
  fail "E: a duplicated finding template in reporting.md was accepted"
elif grep -qi 'template' <<<"$output"; then
  pass "E: a duplicated finding template in reporting.md is rejected"
else
  fail "E: rejected without naming the duplicated template: $output"
fi

# --- failure path: the body-less re-review rule removed --------------------
bodyless="$(make_fixture bodyless)"
sed -i.bak '/body-less/d' "$bodyless/review-contract.md"
if output="$(run_verifier "$bodyless")"; then
  fail "F: a contract without the body-less rule was accepted"
elif grep -qi 'body-less' <<<"$output"; then
  pass "F: a contract without the body-less rule is rejected"
else
  fail "F: rejected without naming the body-less rule: $output"
fi

# --- failure path: the Superseded line removed -----------------------------
superseded="$(make_fixture superseded)"
sed -i.bak '/Superseded:/d' "$superseded/review-contract.md"
if output="$(run_verifier "$superseded")"; then
  fail "G: a re-review preamble without Superseded was accepted"
elif grep -qi 'superseded' <<<"$output"; then
  pass "G: a re-review preamble without Superseded is rejected"
else
  fail "G: rejected without naming the Superseded field: $output"
fi

if ((failures > 0)); then
  echo "review surface tests failed: $failures" >&2
  exit 1
fi

echo "review surface tests passed"
