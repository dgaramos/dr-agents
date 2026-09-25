#!/usr/bin/env bash
# Guards the surface-metadata declarations from dr-agents#444.
#
# The rules under test are declarative: they hold a surface to what it says
# about itself. That makes fixtures the only way to reach them -- the real tree
# is expected to be valid, so a suite that only ran against the real tree would
# pass whether or not the rules were wired at all.
#
# Each negative fixture asserts TWO things: that the gate fails, and that the
# message names the file and the offending value. Exit status alone would pass
# against a gate failing for an unrelated reason, which is the failure this
# suite exists to rule out.
set -euo pipefail

readonly repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The validator is sourced out of bin/check rather than reimplemented here. A
# copy would pass while the shipped block was wrong -- the same reasoning
# tests/test_stub_version_guard.sh records for the stub detector.
sed -n '/^surface_paths() {/,/^validate_surface_metadata \.$/p' "$repo_root/bin/check" \
  | sed '$d' > "$tmp/validator.sh"
[[ -s "$tmp/validator.sh" ]] || { echo "FAIL: could not extract the validator from bin/check" >&2; exit 1; }
# shellcheck disable=SC1090
source "$tmp/validator.sh"

write_surface() {
  local path="$1"; shift
  mkdir -p "$(dirname "$path")"
  { echo '---'; printf '%s\n' "$@"; echo '---'; echo; echo '# fixture'; } > "$path"
}

valid_surface() {
  write_surface "$1" \
    "name: fixture" \
    "description: A fixture surface." \
    "visibility: public" \
    "effects: [read-only]" \
    "gates: [none]"
}

# Runs the validator over an isolated fixture root and prints its messages.
run_validator() {
  local fixture_root="$1"
  surface_metadata_failed=0
  validate_surface_metadata "$fixture_root" 2>&1 || true
  compare_surface_counterparts "$fixture_root" 2>&1 || true
  printf '%s' "$surface_metadata_failed" > "$fixture_root/.failed"
}

new_root() {
  local name="$1"
  local dir="$tmp/$name"
  mkdir -p "$dir/plugins/claudio-dr/skills/fixture" "$dir/plugins/cody-dr/skills/fixture"
  printf '%s' "$dir"
}

assert_rejects() {
  local label="$1" dir="$2" expected="$3"
  local output
  output="$(run_validator "$dir" 2>&1)"
  [[ "$(< "$dir/.failed")" == "1" ]] \
    || { echo "FAIL: $label was accepted; expected rejection" >&2; exit 1; }
  grep -qF "$expected" <<<"$output" \
    || { echo "FAIL: $label did not name '$expected'; got: $output" >&2; exit 1; }
  echo "ok   rejects $label"
}

assert_accepts() {
  local label="$1" dir="$2"
  local output
  output="$(run_validator "$dir" 2>&1)"
  [[ "$(< "$dir/.failed")" == "0" ]] \
    || { echo "FAIL: $label was rejected; got: $output" >&2; exit 1; }
  echo "ok   accepts $label"
}

# --- positive control ------------------------------------------------------
d="$(new_root positive)"
valid_surface "$d/plugins/claudio-dr/skills/fixture/SKILL.md"
valid_surface "$d/plugins/cody-dr/skills/fixture/SKILL.md"
assert_accepts "a well-formed counterpart pair" "$d"

# --- missing fields --------------------------------------------------------
for field in name description visibility effects gates; do
  d="$(new_root "missing-$field")"
  mapfile -t lines < <(printf '%s\n' \
    "name: fixture" "description: A fixture surface." \
    "visibility: public" "effects: [read-only]" "gates: [none]" \
    | grep -v "^$field:")
  write_surface "$d/plugins/claudio-dr/skills/fixture/SKILL.md" "${lines[@]}"
  rm -rf "$d/plugins/cody-dr"
  assert_rejects "a surface missing $field" "$d" "missing required field: $field"
done

# --- values outside the vocabulary -----------------------------------------
d="$(new_root bad-visibility)"
write_surface "$d/plugins/claudio-dr/skills/fixture/SKILL.md" \
  "name: fixture" "description: d" "visibility: hidden" "effects: [read-only]" "gates: [none]"
rm -rf "$d/plugins/cody-dr"
assert_rejects "visibility outside the vocabulary" "$d" "declares visibility: hidden"

d="$(new_root bad-effect)"
write_surface "$d/plugins/claudio-dr/skills/fixture/SKILL.md" \
  "name: fixture" "description: d" "visibility: public" "effects: [deletes-universe]" "gates: [none]"
rm -rf "$d/plugins/cody-dr"
assert_rejects "an effect outside the vocabulary" "$d" "declares effects: deletes-universe"

d="$(new_root bad-gate)"
write_surface "$d/plugins/claudio-dr/skills/fixture/SKILL.md" \
  "name: fixture" "description: d" "visibility: public" "effects: [read-only]" "gates: [vibes]"
rm -rf "$d/plugins/cody-dr"
assert_rejects "a gate outside the vocabulary" "$d" "declares gates: vibes"

# --- exclusivity -----------------------------------------------------------
d="$(new_root read-only-not-exclusive)"
write_surface "$d/plugins/claudio-dr/skills/fixture/SKILL.md" \
  "name: fixture" "description: d" "visibility: public" \
  "effects: [read-only, writes-workspace]" "gates: [none]"
rm -rf "$d/plugins/cody-dr"
assert_rejects "read-only alongside another effect" "$d" "it is exclusive"

d="$(new_root none-not-exclusive)"
write_surface "$d/plugins/claudio-dr/skills/fixture/SKILL.md" \
  "name: fixture" "description: d" "visibility: public" \
  "effects: [read-only]" "gates: [none, approval-checkpoint]"
rm -rf "$d/plugins/cody-dr"
assert_rejects "none alongside another gate" "$d" "it is exclusive"

# --- the publication implication -------------------------------------------
d="$(new_root publishes-ungated)"
write_surface "$d/plugins/claudio-dr/skills/fixture/SKILL.md" \
  "name: fixture" "description: d" "visibility: public" "effects: [publishes]" "gates: [none]"
rm -rf "$d/plugins/cody-dr"
assert_rejects "publishes without explicit-authorization" "$d" \
  "declares publishes without explicit-authorization in gates"

d="$(new_root publishes-gated)"
for side in claudio cody; do
  write_surface "$d/plugins/$side-dr/skills/fixture/SKILL.md" \
    "name: fixture" "description: d" "visibility: internal" \
    "effects: [writes-workspace, publishes]" "gates: [explicit-authorization]"
done
assert_accepts "publishes with explicit-authorization" "$d"

# --- parity ----------------------------------------------------------------
d="$(new_root parity)"
valid_surface "$d/plugins/claudio-dr/skills/fixture/SKILL.md"
write_surface "$d/plugins/cody-dr/skills/fixture/SKILL.md" \
  "name: fixture" "description: d" "visibility: internal" "effects: [read-only]" "gates: [none]"
assert_rejects "counterparts disagreeing on visibility" "$d" "disagree on visibility"

# --- derivation, not enumeration -------------------------------------------
# A surface no list in bin/check mentions must still be validated. This is the
# anti-drift assertion: it must fail loudly if derivation is ever replaced by an
# enumeration of known surface names.
d="$(new_root derived)"
valid_surface "$d/plugins/claudio-dr/skills/fixture/SKILL.md"
valid_surface "$d/plugins/cody-dr/skills/fixture/SKILL.md"
write_surface "$d/plugins/claudio-dr/skills/never-mentioned-anywhere/SKILL.md" \
  "name: never-mentioned-anywhere" "description: d" "visibility: public" "effects: [read-only]"
rm -rf "$d/plugins/cody-dr/skills/never-mentioned-anywhere"
assert_rejects "a surface absent from every list in bin/check" "$d" \
  "never-mentioned-anywhere/SKILL.md is missing required field: gates"

# --- every violation reported, not merely the first ------------------------
d="$(new_root all-violations)"
write_surface "$d/plugins/claudio-dr/skills/fixture/SKILL.md" \
  "name: fixture" "description: d" "visibility: public"
rm -rf "$d/plugins/cody-dr"
output="$(run_validator "$d" 2>&1)"
[[ "$(grep -c 'missing required field' <<<"$output")" -ge 2 ]] \
  || { echo "FAIL: only the first violation was reported; got: $output" >&2; exit 1; }
echo "ok   reports every violation, not merely the first"

echo "surface metadata tests passed"
