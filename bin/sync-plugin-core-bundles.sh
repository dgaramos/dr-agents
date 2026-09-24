#!/usr/bin/env bash
set -euo pipefail

# Core remains the only editable source for portable contracts. Plugin-local
# copies are distribution artifacts because marketplace installations contain
# only the selected plugin directory.
readonly source_dir="core"
readonly plugin_dirs=(
  "plugins/cody-dr"
  "plugins/claudio-dr"
)

# Every bundled Markdown file opens with a provenance marker naming its source
# and this script. Without it a bundled contract is byte-identical to the file
# it was generated from, and nothing on the page says so: a reviewer on
# dr-agents#416 anchored a finding on a bundled path as though the text were
# authored there. An HTML comment is invisible in rendered Markdown and present
# in the raw view and in diffs, which is where that mistake is made.
marker_for() {
  printf '<!-- generated from %s by bin/sync-plugin-core-bundles.sh -- do not edit -->\n' "$1"
}

# Building the expected tree and comparing against it is the same operation as
# writing it, so --check and the write share one implementation. A second copy
# of the rule is what drifts.
materialize() {
  local dest="$1"
  mkdir -p "$dest"
  rsync -a --delete --exclude='.gitkeep' "$source_dir/" "$dest/"
  local bundled relative marker
  while IFS= read -r bundled; do
    relative="${bundled#"$dest"/}"
    marker="$(marker_for "$source_dir/$relative")"
    # A SKILL.md opens with YAML frontmatter, and the frontmatter validator in
    # bin/check requires `---` on line 1. Putting the marker first breaks every
    # bundled skill, so it goes after the closing delimiter instead. Caught by
    # the gate on dr-agents#416 rather than by inspection.
    if [[ "$(head -1 "$bundled")" == "---" ]]; then
      awk -v marker="$marker" '
        NR == 1 { print; next }
        !inserted && $0 == "---" { print; print ""; print marker; inserted = 1; next }
        { print }
      ' "$bundled" >"$bundled.marked"
    else
      printf '%s\n%s\n' "$marker" "$(cat "$bundled")" >"$bundled.marked"
    fi
    mv "$bundled.marked" "$bundled"
  done < <(find "$dest" -type f -name '*.md')
}

if [[ "${1:-}" == "--check" ]]; then
  expected="$(mktemp -d)"
  trap 'rm -rf "$expected"' EXIT
  for plugin_dir in "${plugin_dirs[@]}"; do
    materialize "$expected/$(basename "$plugin_dir")"
    if ! diff -ru --exclude='.gitkeep' "$expected/$(basename "$plugin_dir")" "$plugin_dir/core"; then
      echo "core bundle drift: $plugin_dir/core must match $source_dir" >&2
      exit 1
    fi
  done
  exit 0
fi

if [[ $# -ne 0 ]]; then
  echo "usage: $0 [--check]" >&2
  exit 2
fi

for plugin_dir in "${plugin_dirs[@]}"; do
  materialize "$plugin_dir/core"
done
