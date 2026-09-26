#!/usr/bin/env bash
# Verify two catalog invariants that hold by habit rather than by enforcement.
#
# 1. Both adapter manifests must declare the same component directory keys.
#    plugins/claudio-dr/ shipped seven agents while its manifest declared only
#    skills; they loaded because Claude Code discovers them by convention, which
#    is a platform behaviour this catalog does not control. Anything reading a
#    manifest to learn what a plugin contains saw agents for one adapter and
#    none for the other.
#
# 2. Skill directory names must be identical across adapters. bin/check pairs
#    counterparts by substituting the adapter prefix in the path, which works
#    for skills only because their directory names happen to match -- there is
#    no prefix to substitute. A skill added as skills/cody-guide/ maps to itself
#    and the guard then demands a claudio path nobody intended, failing with a
#    message about a missing file rather than about the naming mistake.
#
# Both sets are derived from the tree. A fixed list of component keys or skill
# names passes today and fails for being correct the day something is added.
set -euo pipefail

root="${1:-.}"
failed=0

claudio_manifest="$root/plugins/claudio-dr/.claude-plugin/plugin.json"
cody_manifest="$root/plugins/cody-dr/.codex-plugin/plugin.json"

# Component keys are the manifest entries that point at bundled content.
# Deriving them by shape rather than by name means a third component type is
# covered the day it is introduced, with no list to update. Codex-only
# presentation fields such as `interface` are objects, not paths, so they are
# not components and are legitimately asymmetric.
#
# dr-agents#436 follow-up: the two hosts encode the same component differently.
# Claude Code's manifest schema takes `agents` as an array of `.md` file paths
# and rejects a directory string with `agents: Invalid input`, while Codex takes
# the directory. Parity is about WHICH components an adapter declares, not about
# how each host spells them, so a relative path and an array of relative paths
# both count as one declaration. Restricting this to plain strings would make a
# valid Claude manifest read as a missing component.
component_keys() {
  jq -r '
    def is_path: type == "string" and startswith("./");
    to_entries[]
    | select(
        (.value | is_path)
        or ((.value | type == "array") and (.value | length > 0) and (.value | all(is_path)))
      )
    | .key
  ' "$1" | sort
}

for manifest in "$claudio_manifest" "$cody_manifest"; do
  [[ -f "$manifest" ]] || { echo "catalog-parity: manifest not found: $manifest" >&2; exit 1; }
done

claudio_keys="$(component_keys "$claudio_manifest")"
cody_keys="$(component_keys "$cody_manifest")"

while IFS= read -r key; do
  [[ -n "$key" ]] || continue
  echo "catalog-parity: $cody_manifest declares component '$key' but $claudio_manifest does not" >&2
  failed=1
done < <(comm -13 <(printf '%s\n' "$claudio_keys") <(printf '%s\n' "$cody_keys"))

while IFS= read -r key; do
  [[ -n "$key" ]] || continue
  echo "catalog-parity: $claudio_manifest declares component '$key' but $cody_manifest does not" >&2
  failed=1
done < <(comm -23 <(printf '%s\n' "$claudio_keys") <(printf '%s\n' "$cody_keys"))

skill_dirs() {
  local adapter="$1"
  find "$root/plugins/$adapter/skills" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort
}

claudio_skills="$(skill_dirs claudio-dr)"
cody_skills="$(skill_dirs cody-dr)"

report_skill_gap() {
  local name="$1" present="$2" missing="$3"
  echo "catalog-parity: skill directory '$name' exists in $present but not in $missing" >&2
  case "$name" in
    claudio-*|cody-*)
      echo "catalog-parity:   '$name' carries an adapter prefix; skill directories are named identically in both adapters, and only agent filenames are prefixed" >&2 ;;
  esac
  failed=1
}

while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  report_skill_gap "$name" claudio-dr cody-dr
done < <(comm -23 <(printf '%s\n' "$claudio_skills") <(printf '%s\n' "$cody_skills"))

while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  report_skill_gap "$name" cody-dr claudio-dr
done < <(comm -13 <(printf '%s\n' "$claudio_skills") <(printf '%s\n' "$cody_skills"))

exit "$failed"
