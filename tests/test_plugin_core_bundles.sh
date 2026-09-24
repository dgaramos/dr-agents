#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

bin/sync-plugin-core-bundles.sh --check

temporary_root="$(mktemp -d)"
trap 'rm -rf "$temporary_root"' EXIT

for plugin in cody-dr claudio-dr; do
  artifact_root="$temporary_root/$plugin"
  cp -R "plugins/$plugin" "$artifact_root"

  # Bundle CONTENT is asserted once, by the --check above, which compares each
  # bundle against the same materialization the write path produces. A second
  # byte-identity diff against core/ here was a duplicate of that rule, and it
  # broke the moment the generator began emitting a provenance marker -- two
  # implementations of one rule, exactly the drift this repository documents.
  # What remains below is this test's own assertion: every core/ path a plugin
  # references must exist inside an installed copy of that plugin alone.
  while IFS= read -r contract_path; do
    test -f "$artifact_root/$contract_path"
  done < <(
    grep -rhoE --include='*.md' 'core/[A-Za-z0-9_./-]+\.(md|sh|yaml)' "plugins/$plugin" \
      | sort -u
  )
done
