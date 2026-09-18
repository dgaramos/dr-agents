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

# --- failure path: the verdict strip no longer leads the summary -----------
verdict="$(make_fixture verdict)"
# Move the verdict line to the end of the summary field run, reproducing the
# pre-#342 ordering where the verdict sat below the scope and checks fields.
sed -i.bak '/^\*\*Verdict:\*\*/d' "$verdict/review-contract.md"
if output="$(run_verifier "$verdict")"; then
  fail "H: a summary without a leading verdict strip was accepted"
elif grep -qi 'verdict' <<<"$output"; then
  pass "H: a summary without a leading verdict strip is rejected"
else
  fail "H: rejected without naming the verdict strip: $output"
fi

# --- edge case: the verdict strip must stay inside its rendered budget ------
# The acceptance signal for the strip is rendered, not source, lines: a strip
# that wraps on a narrow viewport pushes the counts off the first screen even
# though the source shows one line.
budget="$(make_fixture budget)"
awk '
  /^\*\*Verdict:\*\*/ && !done {
    printf "%s · <a very long trailing clause that pushes this strip far past any sensible rendered budget and wraps on a phone>\n", $0
    done = 1
    next
  }
  { print }
' "$budget/review-contract.md" >"$budget/patched" &&
  mv "$budget/patched" "$budget/review-contract.md"
if output="$(run_verifier "$budget")"; then
  fail "H2: an over-long verdict strip was accepted"
elif grep -qi 'budget\|too long' <<<"$output"; then
  pass "H2: an over-long verdict strip is rejected"
else
  fail "H2: rejected without naming the strip budget: $output"
fi

# --- failure path: the required Next step field removed --------------------
next_step="$(make_fixture next_step)"
sed -i.bak '/^\*\*Next step:\*\*/d' "$next_step/review-contract.md"
if output="$(run_verifier "$next_step")"; then
  fail "I: a summary without the Next step field was accepted"
elif grep -qi 'next step' <<<"$output"; then
  pass "I: a summary without the Next step field is rejected"
else
  fail "I: rejected without naming the Next step field: $output"
fi

# --- failure path: the collapsed scope block removed -----------------------
collapsed="$(make_fixture collapsed)"
sed -i.bak '/<summary>Scope, checks and limits<\/summary>/d' \
  "$collapsed/review-contract.md"
if output="$(run_verifier "$collapsed")"; then
  fail "J: a summary without the collapsed scope block was accepted"
elif grep -qi 'scope' <<<"$output"; then
  pass "J: a summary without the collapsed scope block is rejected"
else
  fail "J: rejected without naming the scope block: $output"
fi

# --- failure path: a scope field left outside the collapsed block ----------
outside="$(make_fixture outside)"
# Promote Risk axes back above the collapsed block, where it competes with the
# verdict for the first rendered lines.
sed -i.bak '/^\*\*Risk axes:\*\*/d' "$outside/review-contract.md"
awk '
  /^\*\*Next step:\*\*/ {
    print
    print "**Risk axes:** <evaluated>; not applicable: <axes>"
    next
  }
  { print }
' "$outside/review-contract.md" >"$outside/patched" &&
  mv "$outside/patched" "$outside/review-contract.md"
if output="$(run_verifier "$outside")"; then
  fail "J2: a scope field outside the collapsed block was accepted"
elif grep -qi 'risk axes' <<<"$output"; then
  pass "J2: a scope field outside the collapsed block is rejected"
else
  fail "J2: rejected without naming the misplaced field: $output"
fi

# --- failure path: the Checks line back to an open-ended list --------------
checks="$(make_fixture checks)"
sed -i.bak 's/^\*\*Checks:\*\*.*/**Checks:** <consulted results>; not run: <reason or none>/' \
  "$checks/review-contract.md"
if output="$(run_verifier "$checks")"; then
  fail "K: an untrimmed Checks line was accepted"
elif grep -qi 'checks' <<<"$output"; then
  pass "K: an untrimmed Checks line is rejected"
else
  fail "K: rejected without naming the Checks line: $output"
fi

# --- failure path: a size gate removed -------------------------------------
for gate_case in Walkthrough "Behavior map" "Pre-merge"; do
  gate_fixture="$(make_fixture "gate_$(tr ' -' '__' <<<"$gate_case")")"
  sed -i.bak "/^Emit the ${gate_case}/d" "$gate_fixture/review-contract.md"
  if output="$(run_verifier "$gate_fixture")"; then
    fail "L: the ${gate_case} size gate could be removed"
  elif grep -qi "${gate_case}" <<<"$output"; then
    pass "L: removing the ${gate_case} size gate is rejected"
  else
    fail "L: removing the ${gate_case} gate was rejected without naming it: $output"
  fi
done

# --- failure path: a confidence percentage back in the finding template ----
percentage="$(make_fixture percentage)"
sed -i.bak 's/^\*\*Evidence:\*\* `<file:line>` — <verified fact>\./**Evidence:** `<file:line>` — <verified fact>; confidence: <N>\/100./' \
  "$percentage/review-contract.md"
if output="$(run_verifier "$percentage")"; then
  fail "M: a confidence percentage in the published finding was accepted"
elif grep -qi 'confidence' <<<"$output"; then
  pass "M: a confidence percentage in the published finding is rejected"
else
  fail "M: rejected without naming the confidence value: $output"
fi

# --- failure path: a confidence percentage back in the example -------------
example_percentage="$(make_fixture example_percentage)"
printf '\n**Evidence:** `api/handler.py:48` — the field is gone; confidence: 92/100.\n' \
  >>"$example_percentage/generic-pr-review.md"
if output="$(run_verifier "$example_percentage")"; then
  fail "M2: a confidence percentage in the example was accepted"
elif grep -qi 'confidence' <<<"$output"; then
  pass "M2: a confidence percentage in the example is rejected"
else
  fail "M2: rejected without naming the confidence value: $output"
fi

# --- edge case: the >= 80/100 gate is not a published percentage -----------
# Hiding the percentage from the reader must not delete the reviewer-internal
# threshold, and the threshold's own `80/100` must not trip the check above.
gate="$(make_fixture gate)"
if output="$(run_verifier "$gate")"; then
  pass "N: the reviewer-internal >= 80/100 gate is allowed to remain"
else
  fail "N: the retained confidence gate was rejected: $output"
fi

gate_removed="$(make_fixture gate_removed)"
sed -i.bak 's|confidence `>= 80/100`|no particular confidence|' \
  "$gate_removed/review-contract.md"
if output="$(run_verifier "$gate_removed")"; then
  fail "N2: a contract without the confidence gate was accepted"
elif grep -qi 'gate\|80' <<<"$output"; then
  pass "N2: removing the confidence gate is rejected"
else
  fail "N2: rejected without naming the confidence gate: $output"
fi

# --- failure path: manifest and terminal record of confidence removed ------
manifest="$(make_fixture manifest)"
sed -i.bak '/non-published `confidence`/d' "$manifest/review-contract.md"
if output="$(run_verifier "$manifest")"; then
  fail "N3: dropping confidence from the manifest record was accepted"
elif grep -qi 'manifest' <<<"$output"; then
  pass "N3: dropping confidence from the manifest record is rejected"
else
  fail "N3: rejected without naming the manifest record: $output"
fi

# --- regression: Publication hidden inside the collapsed scope block -------
# The published-body field scan stopped at the first non-field line. Once #342
# moved the scope fields into <details>, a scan that stops at the block opener
# would report a clean body while `Publication:` shipped inside it. This case
# fails against that earlier scan and is the reason it was widened.
hidden="$(make_fixture hidden)"
awk '
  /<summary>Scope, checks and limits<\/summary>/ {
    print
    print ""
    print "**Publication:** `<not requested|not published|published by <reviewer name>>`"
    next
  }
  { print }
' "$hidden/review-contract.md" >"$hidden/patched" &&
  mv "$hidden/patched" "$hidden/review-contract.md"
if output="$(run_verifier "$hidden")"; then
  fail "O: a Publication field hidden in the collapsed scope block was accepted"
elif grep -qi 'publication' <<<"$output"; then
  pass "O: a Publication field hidden in the collapsed scope block is rejected"
else
  fail "O: rejected without naming the publication field: $output"
fi

if ((failures > 0)); then
  echo "review surface tests failed: $failures" >&2
  exit 1
fi

echo "review surface tests passed"
