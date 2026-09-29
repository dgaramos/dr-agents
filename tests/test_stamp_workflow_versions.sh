#!/usr/bin/env bash
# Guards the derived stub version marker (bin/stamp-workflow-versions).
#
# The marker on line 1 of every plugins/*/workflows/publish-*.yml used to be
# maintained by hand and held in place by two per-adapter loops in bin/check
# that named both plugins and both manifest paths. An assertion can only report
# the defect, and a hand-maintained list of adapters drifts the day a third one
# is added. The marker is now DERIVED from each plugin's own manifest.
#
# So the properties worth testing are the derivation's, not a marker's:
#
#   - it reads the version from the plugin's manifest wherever that manifest
#     lives, because the two adapters do not share its filename
#     (.claude-plugin vs .codex-plugin);
#   - it covers a plugin nobody added here, discovered from the tree;
#   - --check fails on a stale marker AND on an absent one, since both are the
#     same defect to bin/install's drift detection; and
#   - stamping is idempotent and rewrites nothing but line 1.
#
# Every case runs the REAL script against a fixture tree, never the checkout:
# the script rewrites files in place, and a test that mutates the working tree
# to prove the writer works is a test that can lose uncommitted work.
set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly script="$root/bin/stamp-workflow-versions"

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
pass() { echo "ok: $*"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Build a fixture tree: the real script, plus plugins whose manifests and stubs
# this test controls. `manifest_dir` differs per plugin on purpose.
make_fixture() {
  local dir="$1"
  rm -rf "$dir"
  mkdir -p "$dir/bin"
  cp "$script" "$dir/bin/stamp-workflow-versions"

  local spec plugin manifest_dir version
  for spec in "claudio-dr:.claude-plugin:0.9.1" "cody-dr:.codex-plugin:0.9.1" "third-dr:.third-plugin:2.0.0"; do
    IFS=: read -r plugin manifest_dir version <<<"$spec"
    mkdir -p "$dir/plugins/$plugin/$manifest_dir" "$dir/plugins/$plugin/workflows"
    printf '{\n  "name": "%s",\n  "version": "%s"\n}\n' "$plugin" "$version" \
      > "$dir/plugins/$plugin/$manifest_dir/plugin.json"
    printf '# %s: v%s\nname: publish\njobs: {}\n' "$plugin" "$version" \
      > "$dir/plugins/$plugin/workflows/publish-$plugin-issue.yml"
  done
}

fixture="$tmp/repo"

# -- a correctly stamped tree passes, and covers the plugin nobody enumerated --
make_fixture "$fixture"
if out="$("$fixture/bin/stamp-workflow-versions" --check 2>&1)"; then
  if [[ "$out" == *"3 stub(s)"* ]]; then
    pass "--check passes a derived tree and counts all 3 stubs, including third-dr"
  else
    fail "--check passed but did not report all 3 stubs; output: $out"
  fi
else
  fail "--check rejected a correctly stamped tree; output: $out"
fi

# The third plugin proves discovery is from the tree. If the script enumerated
# adapters, third-dr's wrong marker below would pass unnoticed.
printf '# third-dr: v0.0.1\nname: publish\njobs: {}\n' \
  > "$fixture/plugins/third-dr/workflows/publish-third-dr-issue.yml"
if "$fixture/bin/stamp-workflow-versions" --check >/dev/null 2>&1; then
  fail "--check passed a stale marker on a plugin this test never named"
else
  pass "--check fails a stale marker on a plugin discovered from the tree"
fi

# -- the version comes from the plugin's own manifest, not a shared one --
make_fixture "$fixture"
sed -i'' -e 's/"2.0.0"/"2.5.0"/' "$fixture/plugins/third-dr/.third-plugin/plugin.json"
"$fixture/bin/stamp-workflow-versions" >/dev/null 2>&1 || true
third_marker="$(head -1 "$fixture/plugins/third-dr/workflows/publish-third-dr-issue.yml")"
claudio_marker="$(head -1 "$fixture/plugins/claudio-dr/workflows/publish-claudio-dr-issue.yml")"
if [[ "$third_marker" == "# third-dr: v2.5.0" && "$claudio_marker" == "# claudio-dr: v0.9.1" ]]; then
  pass "each stub is stamped from its own plugin's manifest, whatever its directory is named"
else
  fail "stamping crossed manifests: third='$third_marker' claudio='$claudio_marker'"
fi

# -- an absent marker is the same defect as a stale one --
make_fixture "$fixture"
target="$fixture/plugins/cody-dr/workflows/publish-cody-dr-issue.yml"
printf 'name: publish\njobs: {}\n' > "$target"
if "$fixture/bin/stamp-workflow-versions" --check >/dev/null 2>&1; then
  fail "--check passed a stub carrying no marker at all"
else
  pass "--check fails a stub carrying no marker at all"
fi

# Stamping an unmarked stub PREPENDS; it must not consume the first real line.
"$fixture/bin/stamp-workflow-versions" >/dev/null 2>&1 || true
if [[ "$(head -1 "$target")" == "# cody-dr: v0.9.1" && "$(sed -n 2p "$target")" == "name: publish" ]]; then
  pass "stamping an unmarked stub prepends the marker and keeps the first real line"
else
  fail "stamping an unmarked stub destroyed content: $(head -2 "$target" | tr '\n' '|')"
fi

# -- stamping is idempotent and touches nothing but line 1 --
make_fixture "$fixture"
sed -i'' -e '1s/.*/# claudio-dr: v0.0.1/' \
  "$fixture/plugins/claudio-dr/workflows/publish-claudio-dr-issue.yml"
"$fixture/bin/stamp-workflow-versions" >/dev/null 2>&1 || true
before="$(find "$fixture/plugins" -name '*.yml' -exec cat {} \; | shasum)"
"$fixture/bin/stamp-workflow-versions" >/dev/null 2>&1 || true
after="$(find "$fixture/plugins" -name '*.yml' -exec cat {} \; | shasum)"
if [[ "$before" == "$after" ]]; then
  pass "stamping twice is idempotent"
else
  fail "a second stamping changed the tree"
fi
rest="$(tail -n +2 "$fixture/plugins/claudio-dr/workflows/publish-claudio-dr-issue.yml")"
if [[ "$rest" == "name: publish
jobs: {}" ]]; then
  pass "stamping rewrites line 1 only"
else
  fail "stamping altered the body: $rest"
fi

# -- an empty tree is an error, not a silent pass (the glob-matched-nothing trap) --
empty="$tmp/empty"
mkdir -p "$empty/bin"
cp "$script" "$empty/bin/stamp-workflow-versions"
mkdir -p "$empty/plugins"
if "$empty/bin/stamp-workflow-versions" --check >/dev/null 2>&1; then
  fail "--check passed a tree with no publisher stubs at all"
else
  pass "--check fails when no publisher stub is found, instead of passing vacuously"
fi

# -- bin/check consumes the derivation rather than re-asserting the marker --
if grep -q 'bin/stamp-workflow-versions --check' "$root/bin/check"; then
  pass "bin/check delegates the marker check to the derivation"
else
  fail "bin/check does not call bin/stamp-workflow-versions --check"
fi
if grep -qE 'claudio_wf_ver|cody_wf_ver' "$root/bin/check"; then
  fail "bin/check still carries per-adapter marker variables"
else
  pass "bin/check no longer names each adapter's manifest to build the marker"
fi

if [[ "$failures" -gt 0 ]]; then
  echo "$failures assertion(s) failed" >&2
  exit 1
fi
echo "stub marker derivation tests passed"
