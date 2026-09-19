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
readonly findings="core/findings-handling/references/findings-contract.md"
readonly profile_contract="core/pr-review/references/profile-contract.md"

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
  cp "$findings" "$dir/findings-contract.md"
  cp "$profile_contract" "$dir/profile-contract.md"
  echo "$dir"
}

run_verifier() {
  local dir="$1"
  bash "$verifier" \
    "$dir/review-contract.md" "$dir/reporting.md" "$dir/generic-pr-review.md" \
    "$dir/findings-contract.md" "$dir/profile-contract.md" 2>&1
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


# --- failure path: the reviewer reply template loses a required field ------
# #347: a reply that drops `Verified on <sha>:` is indistinguishable from the
# restatement the anatomy exists to prevent.
for reply_field in 'Verified on' 'Severity (' 'Status:'; do
  reply_case="$(make_fixture "reply_${reply_field// /_}")"
  grep -vF "**${reply_field}" "$reply_case/review-contract.md" \
    >"$reply_case/patched" && mv "$reply_case/patched" "$reply_case/review-contract.md"
  if output="$(run_verifier "$reply_case")"; then
    fail "P[$reply_field]: a reply template without the field was accepted"
  elif grep -qi 'reply' <<<"$output"; then
    pass "P[$reply_field]: a reply template without the field is rejected"
  else
    fail "P[$reply_field]: rejected without naming the reply template: $output"
  fi
done

# --- failure path: the display-name prefix rule removed --------------------
prefix="$(make_fixture prefix)"
sed -i.bak '/display name/d' "$prefix/review-contract.md"
if output="$(run_verifier "$prefix")"; then
  fail "Q: a contract without the display-name prefix rule was accepted"
elif grep -qi 'display name' <<<"$output"; then
  pass "Q: removing the display-name prefix rule is rejected"
else
  fail "Q: rejected without naming the prefix rule: $output"
fi

# --- failure path: the implementer role marker removed ---------------------
marker="$(make_fixture marker)"
sed -i.bak 's/Fix applied/Change landed/g' "$marker/review-contract.md"
if output="$(run_verifier "$marker")"; then
  fail "R: a contract without the implementer role marker was accepted"
elif grep -qi 'implementer\|Fix applied' <<<"$output"; then
  pass "R: removing the implementer role marker is rejected"
else
  fail "R: rejected without naming the role marker: $output"
fi

# --- failure path: implementer replies allowed as resolution evidence ------
resolution="$(make_fixture resolution)"
sed -i.bak '/never proof of resolution/d' "$resolution/review-contract.md"
if output="$(run_verifier "$resolution")"; then
  fail "R2: a contract that does not exclude implementer replies was accepted"
elif grep -qi 'resolution' <<<"$output"; then
  pass "R2: dropping the implementer resolution exclusion is rejected"
else
  fail "R2: rejected without naming the resolution rule: $output"
fi

# --- failure path: the findings contract stops emitting the marker ---------
findings_case="$(make_fixture findings)"
sed -i.bak 's/Fix applied/Change landed/g' "$findings_case/findings-contract.md"
if output="$(run_verifier "$findings_case")"; then
  fail "S: a findings contract without the role marker was accepted"
elif grep -qi 'findings' <<<"$output"; then
  pass "S: a findings contract without the role marker is rejected"
else
  fail "S: rejected without naming the findings contract: $output"
fi

# --- failure path: the findings contract restates the reply template -------
# The marker must be emitted by reference to review-contract.md, not copied:
# two core files defining one template is the drift #339 removed.
findings_pointer="$(make_fixture findings_pointer)"
sed -i.bak 's|review-contract.md|reporting.md|g' \
  "$findings_pointer/findings-contract.md"
if output="$(run_verifier "$findings_pointer")"; then
  fail "S2: a findings contract that does not point at the canonical template was accepted"
elif grep -qi 'canonical\|points at\|review-contract' <<<"$output"; then
  pass "S2: a findings contract without the canonical pointer is rejected"
else
  fail "S2: rejected without naming the missing pointer: $output"
fi

# --- failure path: the AI-prompt gate removed ------------------------------
prompt_gate="$(make_fixture prompt_gate)"
sed -i.bak '/one-hunk/d' "$prompt_gate/review-contract.md"
if output="$(run_verifier "$prompt_gate")"; then
  fail "T: an ungated AI-agent prompt block was accepted"
elif grep -qi 'one-hunk\|prompt' <<<"$output"; then
  pass "T: an ungated AI-agent prompt block is rejected"
else
  fail "T: rejected without naming the prompt gate: $output"
fi

# --- failure path: committable suggestions no longer stated as never required
suggestion="$(make_fixture suggestion)"
sed -i.bak '/never required/d' "$suggestion/review-contract.md"
if output="$(run_verifier "$suggestion")"; then
  fail "T2: a contract that may require suggestion blocks was accepted"
elif grep -qi 'suggestion' <<<"$output"; then
  pass "T2: dropping the never-required suggestion rule is rejected"
else
  fail "T2: rejected without naming the suggestion rule: $output"
fi

# --- regression: a second AI-agent prompt block appearing later ------------
# #351 tightened the one existing block. A second block elsewhere in the
# contract would carry its own, looser gate and quietly undo that tightening,
# so exactly one block is the assertion, not merely at least one.
second_prompt="$(make_fixture second_prompt)"
printf '\n<details>\n<summary>Prompt for AI agents</summary>\n\nAnything at all.\n\n</details>\n' \
  >>"$second_prompt/review-contract.md"
if output="$(run_verifier "$second_prompt")"; then
  fail "U: a second AI-agent prompt block was accepted"
elif grep -qi 'exactly one\|prompt' <<<"$output"; then
  pass "U: a second AI-agent prompt block is rejected"
else
  fail "U: rejected without naming the duplicate prompt block: $output"
fi

# --- edge case: the shipped prompt block keeps its untrusted marking -------
untrusted="$(make_fixture untrusted)"
sed -i.bak 's/untrusted review data/ordinary review data/' \
  "$untrusted/review-contract.md"
if output="$(run_verifier "$untrusted")"; then
  fail "V: an AI-agent prompt block not marked untrusted was accepted"
elif grep -qi 'untrusted' <<<"$output"; then
  pass "V: an AI-agent prompt block not marked untrusted is rejected"
else
  fail "V: rejected without naming the untrusted marking: $output"
fi

# --- failure path: the Language field missing from the scope block ---------
# dr-agents#349: the resolved prose language and its origin are part of the
# published surface, not reviewer-internal state. A review that renders prose in
# pt-BR without saying so leaves a reader unable to tell a declaration from an
# accident.
language="$(make_fixture language)"
sed -i.bak '/^\*\*Language:\*\*/d' "$language/review-contract.md"
if output="$(run_verifier "$language")"; then
  fail "W: a scope block without the Language field was accepted"
elif grep -qi 'language' <<<"$output"; then
  pass "W: a scope block without the Language field is rejected"
else
  fail "W: rejected without naming the Language field: $output"
fi

# --- failure path: the Language field promoted above the collapsed block ---
language_place="$(make_fixture language_place)"
sed -i.bak '/^\*\*Language:\*\*/d' "$language_place/review-contract.md"
awk '
  /^\*\*Next step:\*\*/ {
    print
    print "**Language:** <language> (source: <profile|README|default>)"
    next
  }
  { print }
' "$language_place/review-contract.md" >"$language_place/patched" &&
  mv "$language_place/patched" "$language_place/review-contract.md"
if output="$(run_verifier "$language_place")"; then
  fail "W2: a Language field above the collapsed block was accepted"
elif grep -qi 'language' <<<"$output"; then
  pass "W2: a Language field above the collapsed block is rejected"
else
  fail "W2: rejected without naming the misplaced field: $output"
fi

# --- failure path: the emitted Language line loses its source token --------
# The language alone is not auditable: `pt-BR` with no origin cannot be checked
# against the profile. This case is scoped to the emitted template line, because
# the word "source" appears throughout the contract's own English prose and a
# whole-file grep would pass while the rendered field said nothing.
language_source="$(make_fixture language_source)"
sed -i.bak 's/^\*\*Language:\*\*.*/**Language:** <language>/' \
  "$language_source/review-contract.md"
if output="$(run_verifier "$language_source")"; then
  fail "W3: an emitted Language field without its source was accepted"
elif grep -qi 'source' <<<"$output"; then
  pass "W3: an emitted Language field without its source is rejected"
else
  fail "W3: rejected without naming the missing source: $output"
fi

# --- failure path: the resolution-order section removed entirely -----------
# Section-scoped, for the same reason as W3: the contract is written in English
# and mentions profiles, READMEs and defaults in many places, so the assertion
# reads only the `### Review language` section's own body.
language_rule="$(make_fixture language_rule)"
awk '
  /^### Review language/ { skipping = 1; next }
  skipping && /^#+ / { skipping = 0 }
  !skipping { print }
' "$language_rule/review-contract.md" >"$language_rule/patched" &&
  mv "$language_rule/patched" "$language_rule/review-contract.md"
if output="$(run_verifier "$language_rule")"; then
  fail "W4: a contract with no review-language rule was accepted"
elif grep -qi 'language' <<<"$output"; then
  pass "W4: a contract with no review-language rule is rejected"
else
  fail "W4: rejected without naming the language rule: $output"
fi

# --- failure path: the English fallback dropped from the resolution order --
# With no terminal source the order has no defined outcome for an undeclared
# repository, and every unresolved review would have to invent one.
language_fallback="$(make_fixture language_fallback)"
awk '
  /^### Review language/ { in_section = 1 }
  in_section && /^#+ / && !/^### Review language/ { in_section = 0 }
  in_section && /source: `default`/ { next }
  { print }
' "$language_fallback/review-contract.md" >"$language_fallback/patched" &&
  mv "$language_fallback/patched" "$language_fallback/review-contract.md"
if output="$(run_verifier "$language_fallback")"; then
  fail "W5: a resolution order without the English fallback was accepted"
elif grep -qi 'default\|fallback' <<<"$output"; then
  pass "W5: a resolution order without the English fallback is rejected"
else
  fail "W5: rejected without naming the missing fallback: $output"
fi

# --- edge case: a resolution token present only outside the section --------
# The sharpest fake-pass risk for a language rule: the contract's own prose is
# English and names profiles, READMEs and defaults in several places, so an
# assertion that greps the file passes while the section it claims to check has
# lost the source. This case removes a source from the section and reintroduces
# every token elsewhere in the file; only a section-scoped assertion rejects it.
language_scope="$(make_fixture language_scope)"
awk '
  /^### Review language/ { in_section = 1 }
  in_section && /^#+ / && !/^### Review language/ { in_section = 0 }
  in_section && /source: `README`/ { next }
  { print }
' "$language_scope/review-contract.md" >"$language_scope/patched" &&
  mv "$language_scope/patched" "$language_scope/review-contract.md"
printf '\nAside: source: `profile`, source: `README`, source: `default`; first\nsource, extensible, badges, section headings, field labels, SHAs.\n' \
  >>"$language_scope/review-contract.md"
if output="$(run_verifier "$language_scope")"; then
  fail "W6: a resolution source present only outside the section was accepted"
elif grep -qi 'README' <<<"$output"; then
  pass "W6: a resolution source present only outside the section is rejected"
else
  fail "W6: rejected without naming the missing source: $output"
fi

# --- failure path: the profile contract drops the optional Language key ----
profile_key="$(make_fixture profile_key)"
sed -i.bak 's/`Language:`/`Idioma:`/g' "$profile_key/profile-contract.md"
if output="$(run_verifier "$profile_key")"; then
  fail "X: a profile contract without the Language key was accepted"
elif grep -qi 'language' <<<"$output"; then
  pass "X: a profile contract without the Language key is rejected"
else
  fail "X: rejected without naming the Language key: $output"
fi

# --- failure path: the profile contract restates the resolution order ------
# Two core files defining one rule is the drift #339 removed from the finding
# template; the profile contract declares the key and points at the canonical
# order rather than carrying a second copy of it.
profile_restate="$(make_fixture profile_restate)"
printf '\nResolution order: profile, then `source: `default`` in English.\n' \
  >>"$profile_restate/profile-contract.md"
if output="$(run_verifier "$profile_restate")"; then
  fail "X2: a profile contract restating the resolution order was accepted"
elif grep -qi 'restate\|canonical\|resolution order' <<<"$output"; then
  pass "X2: a profile contract restating the resolution order is rejected"
else
  fail "X2: rejected without naming the restatement: $output"
fi

# --- AC-04: the repository-declaration slot must be reachable ---------------
# The acceptance run resolved review prose to English on a repository that
# declares another language, because position 2 of the order required the
# profile to name the declaration file and no profile does. The slot was dead
# and every repository fell through to README.

# Z: the order must have the reviewer look for a declaration at the target,
#    not wait to be handed one by the profile.
lang_lookup="$(make_fixture lang_lookup)"
perl -0pi -e 's/\| 2 \| [^\n]*\n/| 2 | a repository-level language declaration the profile names | source: `<declared file>` |\n/' \
  "$lang_lookup/review-contract.md"
perl -0pi -e 's/Look for a repository-level language declaration.*?\n\n//s' \
  "$lang_lookup/review-contract.md"
if output="$(run_verifier "$lang_lookup")"; then
  fail "Z: a contract that never looks for a repository declaration was accepted"
elif grep -qi 'declaration' <<<"$output"; then
  pass "Z: a contract that never looks for a repository declaration is rejected"
else
  fail "Z: rejected for the wrong reason: $output"
fi

# Z2: falling through to README while a declaration exists must be named as a
#     failure, not left as an acceptable default. This is the exact outcome the
#     acceptance run produced.
lang_fallthrough="$(make_fixture lang_fallthrough)"
perl -0pi -e 's/Reaching `README` while such a declaration exists.*?\n\n//s' \
  "$lang_fallthrough/review-contract.md"
if output="$(run_verifier "$lang_fallthrough")"; then
  fail "Z2: a contract that permits silently falling through to README was accepted"
elif grep -qi 'README' <<<"$output"; then
  pass "Z2: a contract that permits silently falling through to README is rejected"
else
  fail "Z2: rejected for the wrong reason: $output"
fi

# --- AC-07: the non-duplication rule must be asserted, not just written ----
# dr-agents#315 T11. A benchmarked run produced zero duplicate threads under
# this rule, but nothing observed the rule itself -- the same shape as the two
# defective assertions found during the epic's delivery.

# Y: the contract must forbid a competing inline comment on an open matching
#    thread, and say the match spans other authors and bots.
duplicate_rule="$(make_fixture duplicate_rule)"
perl -0pi -e 's/For an open matching thread, do not create a new inline\ncomment: [^\n]*\n[^\n]*\n/For an open matching thread, handle it as you see fit.\n/' \
  "$duplicate_rule/review-contract.md"
if output="$(run_verifier "$duplicate_rule")"; then
  fail "Y: a contract without the no-competing-thread rule was accepted"
elif grep -qi 'matching thread\|duplicate' <<<"$output"; then
  pass "Y: a contract without the no-competing-thread rule is rejected"
else
  fail "Y: rejected for the wrong reason: $output"
fi

# Y2: the cross-reviewer clause is the load-bearing half. Without it the rule
#     only covers the reviewer's own threads, which is not what produced the
#     benchmarked zero -- that thread belonged to a different review bot.
cross_reviewer="$(make_fixture cross_reviewer)"
# The clause wraps across two source lines, so a line-based sed silently
# matches nothing and the fixture stays valid -- it did, the first time.
perl -0pi -e 's/even if it was authored by a human or\nanother review bot\./even if it was authored earlier./s' \
  "$cross_reviewer/review-contract.md"
if output="$(run_verifier "$cross_reviewer")"; then
  fail "Y2: a contract without the cross-reviewer clause was accepted"
elif grep -qi 'another review bot\|cross-reviewer\|matching' <<<"$output"; then
  pass "Y2: a contract without the cross-reviewer clause is rejected"
else
  fail "Y2: rejected for the wrong reason: $output"
fi

# Y3: the manifest must route a duplicate finding into `replies` against the
#     existing comment id rather than into a new thread.
manifest_replies="$(make_fixture manifest_replies)"
sed -i.bak 's/`replies` also carries duplicate findings: it references the existing top-level/`replies` also carries assorted extra text: it mentions the existing top-level/' \
  "$manifest_replies/review-contract.md"
if output="$(run_verifier "$manifest_replies")"; then
  fail "Y3: a manifest that does not route duplicates into replies was accepted"
elif grep -qi 'replies\|duplicate' <<<"$output"; then
  pass "Y3: a manifest that does not route duplicates into replies is rejected"
else
  fail "Y3: rejected for the wrong reason: $output"
fi

# Y4: edge case -- the words "duplicate" and "matching thread" appear in this
#     contract's prose elsewhere. Gutting only the rule's section, while those
#     words survive file-wide, must still be rejected. This is the case that
#     fails if the assertions are ever loosened to a whole-file grep.
scoped_only="$(make_fixture scoped_only)"
perl -0pi -e 's/Before creating a finding, load every current review thread.*?evidence location\./Before creating a finding, glance at the threads./s' \
  "$scoped_only/review-contract.md"
printf '\n<!-- duplicate matching thread another review bot -->\n' \
  >>"$scoped_only/review-contract.md"
if output="$(run_verifier "$scoped_only")"; then
  fail "Y4: a gutted rule with the tokens present file-wide was accepted"
else
  pass "Y4: a gutted rule is rejected although its tokens survive file-wide"
fi

# --- AC-01: both first-screen lines are budgeted, in characters -------------
# The strip had a byte budget and Next step had none, although both have to fit
# inside the same three rendered lines. Bytes are also the wrong unit once prose
# follows the target repository's language: accents cost bytes, not width.

# AA: an over-long Next step must be rejected.
long_next="$(make_fixture long_next)"
perl -0pi -e 's/^\*\*Next step:\*\*.*$/"**Next step:** " . ("x" x 160)/me' \
  "$long_next/review-contract.md"
if output="$(run_verifier "$long_next")"; then
  fail "AA: an over-long Next step line was accepted"
elif grep -qi 'next step' <<<"$output"; then
  pass "AA: an over-long Next step line is rejected"
else
  fail "AA: rejected for the wrong reason: $output"
fi

# AB: the budget must be counted in characters. An accented line inside the
#     character budget but over it in bytes must pass -- otherwise the rule
#     charges a language for width it does not occupy.
accented="$(make_fixture accented)"
perl -0pi -e 's/^\*\*Next step:\*\*.*$/"**Next step:** " . ("á" x 100)/me' \
  "$accented/review-contract.md"
if output="$(run_verifier "$accented")"; then
  pass "AB: an accented Next step inside the character budget is accepted"
else
  fail "AB: an accented line within budget was rejected as if bytes were width: $output"
fi

# AC: the contract must say the budget applies to the emitted line, not just
#     the template, and must state the desktop-only scope of the guarantee.
budget_scope="$(make_fixture budget_scope)"
# Substitute the exact phrase. An earlier version of this fixture assumed a
# line break mid-sentence, matched nothing, and let the case pass against an
# unmodified contract.
sed -i.bak 's/measured on the emitted line/measured on the template/' \
  "$budget_scope/review-contract.md"
if output="$(run_verifier "$budget_scope")"; then
  fail "AC: a contract that budgets only the template was accepted"
elif grep -qi 'emitted' <<<"$output"; then
  pass "AC: a contract that budgets only the template is rejected"
else
  fail "AC: rejected for the wrong reason: $output"
fi

if ((failures > 0)); then
  echo "review surface tests failed: $failures" >&2
  exit 1
fi

echo "review surface tests passed"
