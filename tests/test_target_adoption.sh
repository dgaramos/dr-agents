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
  # `|| true` keeps the missing-heading branch below reachable: under
  # `set -euo pipefail` a failing grep in this assignment aborts the whole run
  # before the intended `fail` is ever recorded.
  line="$(grep -n -- "^## ${heading} — " "$file" | head -1 | cut -d: -f1 || true)"
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

echo "== dr-agents#335 ship flows adopt target resolution"

# The three lifecycle contracts that mutate a repository. Each must resolve the
# target before it loads a profile, run every git command inside the resolved
# checkout, and refuse to mutate a checkout it did not expect.
readonly ship_change='core/issue-workflow/references/ship-change-contract.md'
readonly ship_issue='core/issue-workflow/references/ship-issue-contract.md'
readonly start_issue='core/issue-workflow/references/start-issue-contract.md'

for flow_contract in "$ship_change" "$ship_issue" "$start_issue"; do
  assert_contains "$flow_contract" "$contract" \
    "reference the target-resolution contract"
  # RF-06: a mutating flow that runs bare `git` runs it in whatever directory
  # the agent started in. The checkout has to be named at the call site.
  assert_contains "$flow_contract" 'git -C <checkout>' \
    "run git inside the resolved checkout"
done

# AC-08 / RF-11: the shipping and starting summaries lead with provenance.
assert_rf11_lead "$ship_change" 'Ship'
assert_rf11_lead "$ship_issue" 'Ship'
assert_rf11_lead "$start_issue" 'Start'

# AC-09: publisher selection happens against the resolved target...
assert_contains "$ship_change" 'select-publisher.sh' \
  "select the PR publisher against the resolved target"
assert_contains "$ship_change" 'publish-<agent>-pr-metadata.yml' \
  "select the metadata publisher against the resolved target"
# ...and dispatch is repository-qualified. Selecting at the target and then
# dispatching unqualified runs the publisher in the current checkout's
# repository: that is the failed publication dr-agents#404 found, not a detail.
assert_contains "$ship_change" '--repo <target>' \
  "qualify the publisher dispatch with the resolved target"
# The PR that comes back must belong to the target. Verifying the author only
# proves who published, not where.
assert_contains "$ship_change" "the resolved target" \
  "verify the created PR's repository against the resolved target"
assert_contains "$ship_change" 'Metadata publisher:' \
  "report the metadata publisher separately"

# AC-14: the clean-tree and expected-branch gate precedes the first mutation.
# Without it a flow commits into whatever state the resolved checkout was left
# in by unrelated work.
for flow_contract in "$start_issue" "$ship_issue" "$ship_change"; do
  assert_contains "$flow_contract" 'before any mutation' \
    "gate mutation on a clean tree and the expected branch"
  assert_contains "$flow_contract" 'Checkout state:' \
    "report the verified checkout state"
done

for surface in plugins/claudio-dr/skills/start-issue/SKILL.md \
               plugins/claudio-dr/skills/ship-change/SKILL.md \
               plugins/claudio-dr/skills/ship-issue/SKILL.md \
               plugins/claudio-dr/agents/claudio-executor.md; do
  assert_contains "$surface" "$contract" "reference the target-resolution contract"
done

# The executor agents advertise where they work. "in the current repository" is
# the claim this issue retires.
assert_absent 'in the current repository' "'in the current repository'" \
  plugins/claudio-dr/agents/claudio-executor.md \
  plugins/cody-dr/agents/cody-executor.md

assert_parity plugins/claudio-dr/skills/ship-change/SKILL.md \
              plugins/cody-dr/skills/ship-change/SKILL.md
assert_parity plugins/claudio-dr/skills/ship-issue/SKILL.md \
              plugins/cody-dr/skills/ship-issue/SKILL.md
assert_parity plugins/claudio-dr/agents/claudio-executor.md \
              plugins/cody-dr/agents/cody-executor.md

# start-issue cannot reach full parity by design: bin/check requires each
# adapter to carry a *divergent* platform-scoping note (Claude Code worktree
# mechanics vs Codex shell and file tools), and normalize_surface does not
# neutralize it. So parity is asserted on the rest of the file. Everything
# outside that one intentional paragraph must still mirror, which is what
# catches the real divergence: the two adapters described profile discovery in
# different words with different meanings.
strip_platform_note() {
  normalize_surface "$1" | awk '
    /^\*\*Platform-specific detail/ { skipping = 1 }
    skipping && NF == 0 { skipping = 0; next }
    skipping { next }
    { print }
  '
}

assert_parity_outside_platform_note() {
  local claudio="$1" cody="$2"
  if [[ ! -f "$claudio" ]]; then fail "missing $claudio"; return; fi
  if [[ ! -f "$cody" ]]; then fail "missing $cody"; return; fi
  if diff -u <(strip_platform_note "$claudio") <(strip_platform_note "$cody") >/dev/null; then
    pass "parity: $cody mirrors $claudio outside the platform-scoped paragraph"
  else
    fail "parity: $cody does not mirror $claudio outside the platform-scoped paragraph"
    diff -u <(strip_platform_note "$claudio") <(strip_platform_note "$cody") >&2 || true
  fi
}

assert_parity_outside_platform_note plugins/claudio-dr/skills/start-issue/SKILL.md \
                                    plugins/cody-dr/skills/start-issue/SKILL.md

echo "== dr-agents#327 / dr-agents#333 spec authoring adopts target resolution"

# core/spec had no notion of a target, a checkout, or a write at all: the flow
# returned the trio inline. These two issues make it the first *writing*
# adopter, so the assertions cover both halves -- dr-agents#327 owns *when* to
# propose versus write, dr-agents#333 owns *where and how* the write lands.
readonly spec_skill='core/spec/SKILL.md'
readonly spec_contract='core/spec/references/spec-contract.md'

for spec_surface in "$spec_skill" "$spec_contract"; do
  assert_contains "$spec_surface" "$contract" \
    "reference the target-resolution contract"
  # RF-06: the trio is written in the resolved checkout, not in whatever
  # directory the spec agent was invoked from.
  assert_contains "$spec_surface" 'git -C <checkout>' \
    "write the trio inside the resolved checkout"
done

# AC-08 / RF-11: the spec summary leads with provenance like every other
# adopting summary. core/spec is not an adopter today, so these lines are added
# to the block, not reordered within it.
assert_rf11_lead "$spec_skill" 'Spec'
assert_rf11_lead "$spec_contract" 'Spec'

# AC-13 (dr-agents#333), *where*: the target of an authorized spec write is the
# specs repository the caller resolved, reached through the resolver's own
# specs entrypoint -- not the current checkout's origin.
assert_contains "$spec_contract" 'from-specs-repository' \
  "resolve the target from the caller's specs repository"
assert_contains "$spec_contract" 'source: specs-repository' \
  "declare the specs-repository resolution source"

# AC-13, *how*, remote half. This path cannot be exercised at runtime here
# without writing to the specs repository, which this change is not authorized
# to do, so the contract text is its cover.
assert_contains "$spec_contract" 'remote-write.sh' \
  "write through remote-write.sh without a checkout"
assert_contains "$spec_contract" 'mode: remote-only' \
  "name the remote-only mode that selects the remote write path"

# AC-16 (dr-agents#327), *when*: a resolved source with an unauthorized slug
# ends in a proposal carrying the exact invocation, never in an inline-only
# trio that leaves the caller guessing where it belongs.
assert_contains "$spec_contract" 'proposed path specs/<project>/<slug>/' \
  "propose the canonical path for an unauthorized slug"
assert_contains "$spec_skill" 'proposed path specs/<project>/<slug>/' \
  "propose the canonical path for an unauthorized slug"
assert_contains "$spec_contract" 'exact write invocation' \
  "carry the exact write invocation with the proposal"

# The authorized half: branch, index registration, and the pull request.
assert_contains "$spec_contract" 'feat/<slug>' \
  "write the authorized trio on the feat/<slug> branch"
assert_contains "$spec_contract" 'index.md' \
  "register the written slug in the project index"

# RF-09: the PR is opened by the adapter's ship-change flow, which already
# owns App publisher selection, verification, and routing. A spec flow that
# opens its own PR duplicates that contract and drifts from it.
assert_contains "$spec_contract" 'ship-change' \
  "open the pull request through the adapter's ship-change flow"
# Selecting a publisher at the target and then dispatching unqualified runs it
# in the current checkout's repository. That is dr-agents#404 finding F1.
assert_contains "$spec_contract" '--repo <target>' \
  "qualify the publisher dispatch with the resolved target"

# The no-authorization outcome must survive the addition of the write path.
assert_contains "$spec_contract" 'Write: not written' \
  "keep the unauthorized outcome as Write: not written"

# AC-14, applied to the entry point this change creates. Writing a trio commits
# and pushes, so the spec write is a mutating entry point and needs the same
# clean-tree and expected-branch gate the lifecycle contracts carry. The
# dr-agents#406 finding was exactly this gap on a contract a test loop did not
# enumerate.
assert_contains "$spec_contract" 'before any mutation' \
  "gate the authorized write on a clean tree and the expected branch"
assert_contains "$spec_contract" 'Checkout state:' \
  "report the verified checkout state"

for surface in plugins/claudio-dr/agents/claudio-spec.md \
               plugins/cody-dr/agents/cody-spec.md; do
  assert_contains "$surface" "$contract" "reference the target-resolution contract"
done

assert_parity plugins/claudio-dr/agents/claudio-spec.md \
              plugins/cody-dr/agents/cody-spec.md

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
