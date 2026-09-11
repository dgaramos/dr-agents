#!/usr/bin/env bash
# Guards the issue-comment publisher (dr-agents#269).
#
# The six central definitions covered creating and updating an issue, creating a
# pull request, applying pull request metadata, replying in a review thread,
# resolving a thread, and submitting a review. Commenting on an issue had no
# route at all, which is why the evidence comment on dr-agents#260 was published
# by a personal account -- not as the routing contract's proven-unavailable
# fallback, but because the operation did not exist.
#
# These tests execute the REAL script, extracted from the shipped definition,
# against a fake `gh` on PATH. A reimplementation would pass while the shipped
# block was wrong, which is the failure mode this whole publisher family keeps
# hitting.
#
# The property under test that matters most is dr-agents#258's: the comment URL
# must reach the step summary BEFORE the author verification runs, so a red job
# is never read as "nothing was published". A test that only checked the final
# outcome would pass with the two reordered, so the ordering is asserted
# positionally, not by presence.
set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

readonly definition=".github/workflows/reusable-publish-issue-comment.yml"

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
pass() { echo "ok: $*"; }

if [[ ! -f "$definition" ]]; then
  echo "FAIL: $definition does not exist" >&2
  exit 1
fi

# --- extract the shipped script -------------------------------------------
#
# `${{ inputs.agent }}` appears in the run block for the summary heading. It is
# a workflow expression, not shell, so substitute the value GitHub would have
# substituted before the shell ever saw it.
extract_script() {
  ruby -ryaml -e '
    wf = YAML.safe_load(File.read(ARGV[0]), aliases: true)
    step = wf["jobs"]["publish"]["steps"].find { |s| s["id"] == "comment" }
    abort "no step with id comment" unless step && step["run"]
    print step["run"].gsub(/\$\{\{ *inputs\.agent *\}\}/, "claudio")
  ' "$definition"
}

script="$(extract_script)" || { echo "FAIL: cannot extract the comment step" >&2; exit 1; }

# --- the fake gh -----------------------------------------------------------
#
# Records every invocation so a test can assert that NO mutation was attempted,
# which is the only thing that makes `not-published` trustworthy.
make_gh() {
  local bindir="$1" response="$2"
  mkdir -p "$bindir"
  cat > "${bindir}/gh" <<GHEOF
#!/usr/bin/env bash
echo "\$*" >> "\${GH_CALLS}"
cat <<'RESPEOF'
${response}
RESPEOF
GHEOF
  chmod +x "${bindir}/gh"
}

# Runs the extracted script in a throwaway directory with a fake gh, and prints
# the resulting step summary. Returns the script's own exit status.
run_publisher() {
  local response="$1" issue_number="$2" body="$3" expected_author="$4"
  work="$(mktemp -d)"
  export GH_CALLS="${work}/gh-calls"
  export GITHUB_STEP_SUMMARY="${work}/summary.md"
  : > "$GH_CALLS"
  : > "$GITHUB_STEP_SUMMARY"
  make_gh "${work}/bin" "$response"
  (
    cd "$work"
    PATH="${work}/bin:${PATH}" \
    GH_TOKEN=fake-token \
    GITHUB_REPOSITORY=dgaramos/dr-agents \
    ISSUE_NUMBER="$issue_number" \
    BODY="$body" \
    EXPECTED_AUTHOR="$expected_author" \
      bash -c "$script"
  ) >"${work}/stdout" 2>"${work}/stderr"
}

readonly ok_response='{"id": 5626144633, "html_url": "https://github.com/dgaramos/dr-agents/issues/260#issuecomment-5626144633", "user": {"login": "claudio-dr[bot]"}}'
readonly wrong_author_response='{"id": 5626144633, "html_url": "https://github.com/dgaramos/dr-agents/issues/260#issuecomment-5626144633", "user": {"login": "dgaramos"}}'

# --- A. happy path ---------------------------------------------------------
if run_publisher "$ok_response" "260" "Evidence for the migration." "claudio-dr[bot]"; then
  summary="$(cat "$GITHUB_STEP_SUMMARY")"
  if grep -qF 'outcome: `published-ok`' <<<"$summary"; then
    pass "A: a verified comment reports published-ok"
  else
    fail "A: no published-ok in the summary: ${summary}"
  fi
  if grep -qF 'issuecomment-5626144633' <<<"$summary"; then
    pass "A: the comment URL reaches the step summary"
  else
    fail "A: the comment URL is absent from the summary"
  fi
  if grep -q 'POST repos/dgaramos/dr-agents/issues/260/comments' "$GH_CALLS"; then
    pass "A: the comment is POSTed to the requested issue"
  else
    fail "A: no POST to the issue's comments endpoint: $(cat "$GH_CALLS")"
  fi
else
  fail "A: the happy path exited non-zero: $(cat "${work}/stderr")"
fi

# --- B. failure path: the comment exists but the author does not verify ----
#
# The dr-agents#258 shape. The job must go red, and the summary must still name
# the resource and forbid republishing, because the comment is already public.
if run_publisher "$wrong_author_response" "260" "Evidence." "claudio-dr[bot]"; then
  fail "B: an unverified author exited zero"
else
  summary="$(cat "$GITHUB_STEP_SUMMARY")"
  if grep -qF 'outcome: `published-unverified`' <<<"$summary"; then
    pass "B: an unverified author reports published-unverified"
  else
    fail "B: no published-unverified in the summary: ${summary}"
  fi
  if grep -qiF 'do not republish' <<<"$summary"; then
    pass "B: the summary instructs against republishing"
  else
    fail "B: the summary does not instruct against republishing"
  fi
  # The ordering assertion. Presence of both lines is not enough: the whole
  # point of dr-agents#258 is that the identifier precedes the verdict.
  # `|| true` on both: under `set -e` a non-matching grep would kill the script
  # instead of reporting, and a harness that dies is a weaker signal than one
  # that names what is wrong -- it looks identical to an unrelated crash.
  resource_line="$(grep -nF 'issuecomment-5626144633' <<<"$summary" | head -1 | cut -d: -f1 || true)"
  verdict_line="$(grep -nF 'published-unverified' <<<"$summary" | head -1 | cut -d: -f1 || true)"
  if [[ -n "$resource_line" && -n "$verdict_line" && "$resource_line" -lt "$verdict_line" ]]; then
    pass "B: the resource identifier precedes the verdict (#258)"
  else
    fail "B: resource line ${resource_line:-none} does not precede verdict line ${verdict_line:-none}"
  fi
fi

# --- C. edge cases: rejected before any mutation ---------------------------
#
# `not-published` is the only outcome that entitles the reader to retry, so
# emitting it after a mutation would be the worst error this script can make.
# Each case asserts the outcome AND that the fake gh was never called.
assert_not_published() {
  local label="$1" issue_number="$2" body="$3"
  if run_publisher "$ok_response" "$issue_number" "$body" "claudio-dr[bot]"; then
    fail "C: ${label} exited zero"
    return
  fi
  if grep -qF 'outcome: `not-published`' "$GITHUB_STEP_SUMMARY"; then
    pass "C: ${label} reports not-published"
  else
    fail "C: ${label} did not report not-published: $(cat "$GITHUB_STEP_SUMMARY")"
  fi
  if [[ -s "$GH_CALLS" ]]; then
    fail "C: ${label} attempted a mutation: $(cat "$GH_CALLS")"
  else
    pass "C: ${label} attempted no mutation"
  fi
}

assert_not_published "an empty body" "260" ""
assert_not_published "a missing issue number" "" "Evidence."
assert_not_published "a non-numeric issue number" "26a0" "Evidence."
assert_not_published "a zero issue number" "0" "Evidence."

# --- D. the definition stays self-contained --------------------------------
#
# Its value is that it needs no catalog: no checkout, no catalog_ref, and so no
# ref skew of the kind tests/test_reusable_ref_resolution.sh exists to prevent.
# That is also why it does not source .github/scripts/publication-outcome.sh --
# sourcing it would require the very checkout this asserts is absent.
if grep -q 'actions/checkout' "$definition"; then
  fail "D: $definition performs a checkout; it must stay self-contained"
else
  pass "D: $definition performs no checkout"
fi
# Checked against the parsed input list rather than the bare word: the
# definition explains in a comment why it takes no catalog_ref, and a grep would
# call that explanation a violation.
if ruby -ryaml -e '
  wf = YAML.safe_load(File.read(ARGV[0]), aliases: true)
  on = wf["on"] || wf[true]
  exit((on["workflow_call"]["inputs"] || {}).key?("catalog_ref") ? 1 : 0)
' "$definition"; then
  pass "D: $definition declares no catalog_ref input"
else
  fail "D: $definition declares a catalog_ref input; it stages no catalog files"
fi
# Again the invocation, not the word: the definition documents at length why it
# does NOT source this script, and that documentation is the opposite of a
# violation. Matches `source x`, `. x`, and `bash x`.
if grep -qE '^[^#]*(source|\.|bash)[[:space:]]+[^[:space:]]*publication-outcome\.sh' "$definition"; then
  fail "D: $definition sources publication-outcome.sh, which needs a checkout"
else
  pass "D: $definition emits the outcome vocabulary inline"
fi

if [[ "$failures" -gt 0 ]]; then
  echo "issue-comment publisher: ${failures} failure(s)" >&2
  exit 1
fi
echo "issue-comment publisher tests passed"
