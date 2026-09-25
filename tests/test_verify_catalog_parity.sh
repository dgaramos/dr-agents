#!/usr/bin/env bash
# Guards the catalog parity assertions from dr-agents#436.
#
# Both rules hold by habit in the real tree, so fixtures are the only way to
# reach them: a suite running only against the repository would pass whether or
# not the assertions were wired at all.
#
# Each negative case asserts the gate fails AND that the message names the
# offending key or directory. Exit status alone would pass against a script
# failing for an unrelated reason.
set -euo pipefail

readonly repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly script="$repo_root/.github/scripts/verify-catalog-parity.sh"
readonly tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# Builds a fixture catalog. Manifests and skill sets are passed in so each case
# varies exactly one thing.
make_case() {
  local name="$1" claudio_json="$2" cody_json="$3" claudio_skills="$4" cody_skills="$5"
  local dir="$tmp/$name"
  mkdir -p "$dir/plugins/claudio-dr/.claude-plugin" "$dir/plugins/cody-dr/.codex-plugin"
  printf '%s\n' "$claudio_json" > "$dir/plugins/claudio-dr/.claude-plugin/plugin.json"
  printf '%s\n' "$cody_json" > "$dir/plugins/cody-dr/.codex-plugin/plugin.json"
  local skill
  for skill in $claudio_skills; do mkdir -p "$dir/plugins/claudio-dr/skills/$skill"; done
  for skill in $cody_skills; do mkdir -p "$dir/plugins/cody-dr/skills/$skill"; done
  printf '%s' "$dir"
}

run_case() {
  set +e
  CASE_STDERR="$(bash "$script" "$1" 2>&1 >/dev/null)"
  CASE_STATUS=$?
  set -e
}

readonly both='{"name":"x","skills":"./skills/","agents":"./agents/"}'
readonly skills_only='{"name":"x","skills":"./skills/"}'
# Codex ships presentation fields the Claude manifest has no equivalent for.
# They are objects, not directory paths, so they are not components and must not
# be read as an asymmetry.
readonly with_interface='{"name":"x","skills":"./skills/","agents":"./agents/","interface":{"displayName":"X"},"defaultPrompt":"go"}'

# --- Happy path -------------------------------------------------------------
d="$(make_case aligned "$both" "$both" "review-pr spec" "review-pr spec")"
run_case "$d"
[[ "$CASE_STATUS" == 0 ]] || fail "aligned: an aligned catalog was rejected: $CASE_STDERR"
echo "ok   accepts aligned manifests and skill sets"

# --- Codex-only presentation fields are not components ----------------------
d="$(make_case interface_ok "$both" "$with_interface" "review-pr" "review-pr")"
run_case "$d"
[[ "$CASE_STATUS" == 0 ]] ||
  fail "interface_ok: non-directory Codex fields must not read as components: $CASE_STDERR"
echo "ok   ignores Codex-only fields that are not directory paths"

# --- The same component spelled differently by each host --------------------
# PR #452: Claude Code's schema takes `agents` as an ARRAY of `.md` paths and
# rejects the Codex directory string outright. Both manifests still DECLARE
# agents, so this is not an asymmetry -- comparing raw values instead of keys
# would force one host or the other into an invalid manifest.
readonly agents_array='{"name":"x","skills":"./skills/","agents":["./agents/a.md","./agents/b.md"]}'
d="$(make_case array_shape "$agents_array" "$both" "review-pr" "review-pr")"
run_case "$d"
[[ "$CASE_STATUS" == 0 ]] ||
  fail "array_shape: an array-valued component must count as declared: $CASE_STDERR"
echo "ok   treats an array of paths as the same declaration as a directory"

# An array-valued component declared by one adapter only is still an asymmetry.
d="$(make_case array_gap "$agents_array" "$skills_only" "review-pr" "review-pr")"
run_case "$d"
[[ "$CASE_STATUS" != 0 ]] || fail "array_gap: an undeclared array component was accepted"
[[ "$CASE_STDERR" == *agents* ]] ||
  fail "array_gap: the message must name 'agents': $CASE_STDERR"
echo "ok   still catches an array component missing from the other adapter"

# Arrays that do not hold relative paths are not components. An empty array or
# a list of plain strings is configuration, and reading it as a component would
# resurrect the false asymmetry this gate exists to prevent.
readonly non_path_arrays='{"name":"x","skills":"./skills/","agents":"./agents/","capabilities":[],"tags":["review","issues"]}'
d="$(make_case non_path_arrays "$both" "$non_path_arrays" "review-pr" "review-pr")"
run_case "$d"
[[ "$CASE_STATUS" == 0 ]] ||
  fail "non_path_arrays: empty or non-path arrays must not read as components: $CASE_STDERR"
echo "ok   ignores arrays that do not hold relative paths"

# --- The defect this exists for: an undeclared component --------------------
d="$(make_case undeclared "$skills_only" "$both" "review-pr" "review-pr")"
run_case "$d"
[[ "$CASE_STATUS" == 1 ]] || fail "undeclared: a one-sided component declaration was accepted"
grep -qF "declares component 'agents'" <<<"$CASE_STDERR" ||
  fail "undeclared: the failure must name the component key; got: $CASE_STDERR"
echo "ok   rejects a component declared by one manifest only"

# Reported in both directions: deriving from one side makes that side the sole
# source of truth for a set that is supposed to be derived.
d="$(make_case undeclared_reverse "$both" "$skills_only" "review-pr" "review-pr")"
run_case "$d"
[[ "$CASE_STATUS" == 1 ]] || fail "undeclared_reverse: the reverse direction was accepted"
echo "ok   reports an undeclared component in both directions"

# --- Skill directory sets ---------------------------------------------------
d="$(make_case skill_gap "$both" "$both" "review-pr guide" "review-pr")"
run_case "$d"
[[ "$CASE_STATUS" == 1 ]] || fail "skill_gap: a one-sided skill directory was accepted"
grep -qF "skill directory 'guide' exists in claudio-dr but not in cody-dr" <<<"$CASE_STDERR" ||
  fail "skill_gap: the failure must name the directory and the adapter; got: $CASE_STDERR"
echo "ok   rejects a skill directory present in one adapter only"

# --- The naming mistake must be reported as a naming mistake ----------------
# Without this the run still fails, but with a message about a missing file,
# which is the slower failure to debug.
d="$(make_case prefixed "$both" "$both" "review-pr" "review-pr cody-guide")"
run_case "$d"
[[ "$CASE_STATUS" == 1 ]] || fail "prefixed: a prefixed skill directory was accepted"
grep -qF "carries an adapter prefix" <<<"$CASE_STDERR" ||
  fail "prefixed: the failure must identify the naming mistake; got: $CASE_STDERR"
echo "ok   names the adapter-prefix mistake rather than a missing path"

# --- Derived, not enumerated ------------------------------------------------
# A skill pair no list in the repository mentions must still be covered.
d="$(make_case derived "$both" "$both" "never-mentioned-anywhere" "never-mentioned-anywhere")"
run_case "$d"
[[ "$CASE_STATUS" == 0 ]] || fail "derived: an unknown but aligned skill pair was rejected: $CASE_STDERR"
d="$(make_case derived_gap "$both" "$both" "never-mentioned-anywhere" "")"
run_case "$d"
[[ "$CASE_STATUS" == 1 ]] ||
  fail "derived_gap: a skill absent from every list in bin/check was not covered"
echo "ok   covers skills no list in the repository mentions"

# --- The repository's own catalog must satisfy the gate ---------------------
bash "$script" "$repo_root" || fail "catalog: the repository's own catalog fails the parity gate"
echo "ok   the repository's own catalog passes"

echo "PASS: $(basename "${BASH_SOURCE[0]}")"
