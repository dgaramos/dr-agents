#!/usr/bin/env bash
# Assertions for the flows that adopt the target-resolution contract.
#
# Adoption is a contract change, so the executable assertion is a check against
# the contract text itself: an adopting flow must resolve the target before it
# loads a profile, must declare the target in its summary block, and must say
# the same thing in both adapters once identity is normalized.
#
# This file is the unit-level cover. The derived, self-extending forms of the
# same rules belong in bin/check (dr-agents#330) and land after every adopting
# flow does; until then this test is what fails when an adoption regresses.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

pass() {
  echo "ok: $*"
}

# RF-11 is literal: every adopting summary *begins* with the target and profile
# facts. Not "carries them somewhere near the top" -- begins. So this asserts an
# order, not a presence: the first `**Field:**` line under the heading must be
# `**Target:**` and the second must be `**Profile:**`. A window-based presence
# check passes for a summary that buries provenance under a verdict, which is
# exactly the shape RF-11 forbids.
#
# The fence may be three or more backticks, because review-contract.md nests a
# ```md sample inside a ````md fence.
assert_rf11_lead() {
  local file="$1" heading="$2"
  local line fields first second
  line="$(grep -n -- "^## ${heading} — " "$file" | head -1 | cut -d: -f1)"
  if [[ -z "$line" ]]; then
    fail "$file has no '## ${heading} — ' summary block"
    return
  fi
  # The field run is the block of consecutive `**Field:**` lines under the
  # heading, skipping blank lines only. Anything else ends the run.
  fields="$(tail -n +"$((line + 1))" "$file" | awk '
    /^\*\*/ { print; next }
    NF == 0 { next }
    { exit }
  ')"
  first="$(sed -n 1p <<<"$fields")"
  second="$(sed -n 2p <<<"$fields")"
  if [[ "$first" != '**Target:**'* ]]; then
    fail "$file '## ${heading} — ' does not begin with **Target:**; first field is: ${first:-<none>}"
    return
  fi
  if [[ "$second" != '**Profile:**'* ]]; then
    fail "$file '## ${heading} — ' does not carry **Profile:** as its second field; got: ${second:-<none>}"
    return
  fi
  pass "$file '## ${heading} — ' begins with **Target:** then **Profile:**"
}

assert_contains() {
  local file="$1" pattern="$2" label="$3"
  if grep -q -- "$pattern" "$file"; then
    pass "$file $label"
  else
    fail "$file does not $label"
  fi
}

assert_absent() {
  local pattern="$1" label="$2"
  shift 2
  local hit=0 file
  for file in "$@"; do
    if grep -qn -- "$pattern" "$file"; then
      fail "$file still contains $label"
      hit=1
    fi
  done
  if [[ $hit -eq 0 ]]; then
    pass "no adopting surface contains $label"
  fi
}

# Mirrors bin/check's reviewer-surface normalizer: identity tokens collapse to
# one neutral word, the Codex-only `name:` frontmatter line drops, and the two
# plugin-root spellings converge. Nothing else is neutralized, so any other
# divergence between the adapters fails here.
normalize_surface() {
  sed -e 's/Claudio/X/g' -e 's/claudio/x/g' \
      -e 's/Cody/X/g' -e 's/cody/x/g' \
      -e 's/Claude App/X App/g' -e 's/Codex App/X App/g' \
      -e 's|${CLAUDE_PLUGIN_ROOT}|<plugin-root>|g' \
      -e 's|<installed-plugin-root>|<plugin-root>|g' \
      -e '1,/^---$/{/^name: /d;}' "$1"
}

assert_parity() {
  local claudio="$1" cody="$2"
  if [[ ! -f "$claudio" ]]; then fail "missing $claudio"; return; fi
  if [[ ! -f "$cody" ]]; then fail "missing $cody"; return; fi
  if diff -u <(normalize_surface "$claudio") <(normalize_surface "$cody") >/dev/null; then
    pass "parity: $cody mirrors $claudio once identity is normalized"
  else
    fail "parity: $cody does not mirror $claudio once identity is normalized"
    diff -u <(normalize_surface "$claudio") <(normalize_surface "$cody") >&2 || true
  fi
}

readonly contract='core/target-resolution/references/target-resolution-contract.md'

echo "== dr-agents#332 review-pr adopts target resolution"

assert_contains core/pr-review/SKILL.md "$contract" \
  "reference the target-resolution contract"
assert_contains core/pr-review/references/review-contract.md "$contract" \
  "reference the target-resolution contract"
# No exception. RF-11 stays universal in the target-resolution contract and the
# review summary satisfies it: target and profile lead, verdict and next step
# follow. verify-review-surface.sh enforces the same order from the other side.
assert_rf11_lead core/pr-review/references/review-contract.md 'Review'
assert_rf11_lead core/pr-review/references/review-contract.md 'Re-review'

# The third spelling of an absent profile. The contract names exactly two
# cases -- `none (remote-only)` and `none (no profile at checkout)` -- and a
# third one in the adapters means the summary vocabulary is not the contract's.
assert_absent 'checkout not available' "'checkout not available'" \
  plugins/claudio-dr/skills/review-pr/SKILL.md \
  plugins/cody-dr/skills/review-pr/SKILL.md

for surface in plugins/claudio-dr/skills/review-pr/SKILL.md \
               plugins/claudio-dr/agents/claudio-reviewer.md; do
  assert_contains "$surface" "$contract" "reference the target-resolution contract"
done

assert_parity plugins/claudio-dr/skills/review-pr/SKILL.md \
              plugins/cody-dr/skills/review-pr/SKILL.md
assert_parity plugins/claudio-dr/agents/claudio-reviewer.md \
              plugins/cody-dr/agents/cody-reviewer.md

echo "== dr-agents#334 author-issue adopts target resolution"

assert_contains core/issue-authoring/SKILL.md "$contract" \
  "reference the target-resolution contract"
assert_contains core/issue-authoring/references/issue-contract.md "$contract" \
  "reference the target-resolution contract"
assert_rf11_lead core/issue-authoring/references/issue-contract.md 'Issue draft'

# The publisher is selected against the resolved target, not the current
# directory: this is the difference between publishing into the repository the
# issue is for and publishing into whichever checkout the agent happened to
# start in.
assert_contains core/issue-authoring/references/issue-contract.md \
  'select-publisher.sh' "select the publisher against the resolved target"
assert_contains core/issue-authoring/references/issue-contract.md \
  'gh api repos/' "read the issue template remotely in remote-only mode"

# Selecting at the target is not enough: an unqualified dispatch runs in the
# current checkout's repository, so the mechanics must carry the target too.
assert_contains core/issue-authoring/references/issue-contract.md \
  '--repo <target>' "qualify the publisher dispatch with the resolved target"

for surface in plugins/claudio-dr/skills/author-issue/SKILL.md \
               plugins/claudio-dr/agents/claudio-author.md; do
  assert_contains "$surface" "$contract" "reference the target-resolution contract"
done

assert_parity plugins/claudio-dr/skills/author-issue/SKILL.md \
              plugins/cody-dr/skills/author-issue/SKILL.md
assert_parity plugins/claudio-dr/agents/claudio-author.md \
              plugins/cody-dr/agents/cody-author.md

echo "== no adopting surface tells the agent to use the current repository"

shopt -s nullglob
cwd_sentence_hits=0
for surface in plugins/*/skills/*/SKILL.md plugins/*/agents/*.md; do
  case "$surface" in */core/*) continue ;; esac
  if grep -q 'target-resolution' "$surface" \
     && grep -qn 'profile from the current repository' "$surface"; then
    fail "$surface adopts target resolution but still discovers the profile from the current repository"
    cwd_sentence_hits=1
  fi
done
if [[ $cwd_sentence_hits -eq 0 ]]; then
  pass "no adopting surface discovers the profile from the current repository"
fi

if [[ $failures -gt 0 ]]; then
  echo "tests/test_target_adoption.sh: $failures assertion(s) failed" >&2
  exit 1
fi

echo "tests/test_target_adoption.sh: all assertions passed"
