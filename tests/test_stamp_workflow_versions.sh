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
#     same defect to bin/install's drift detection;
#   - stamping is idempotent and rewrites nothing but line 1;
#   - the version read is the manifest's TOP-LEVEL .version, not the first line
#     that happens to contain the word, so a nested metadata.version declared
#     earlier in the file cannot be stamped into every stub; and
#   - the jq and no-jq branches answer identically on every fixture, the
#     property tests/test_install.sh established for bin/install's readers. jq
#     is not a dependency of this repository, so a jq-only parser would fail
#     bin/check on a machine where it passes today.
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

# A PATH that contains no jq, derived from the real PATH rather than from a list
# of tool names: every executable in every PATH directory is symlinked into one
# directory EXCEPT jq. A shim that merely shadows jq would not do — jq lives at
# more than one place in some PATHs, so "prepend a directory" leaves the other
# copy reachable.
nojq_path() {
  local dir="$tmp/nojq-bin" d entry
  if [[ ! -d "$dir" ]]; then
    mkdir -p "$dir"
    local IFS=:
    for d in $PATH; do
      [[ -d "$d" ]] || continue
      for entry in "$d"/*; do
        [[ -f "$entry" && -x "$entry" ]] || continue
        [[ "${entry##*/}" == "jq" ]] && continue
        [[ -e "$dir/${entry##*/}" ]] || ln -s "$entry" "$dir/${entry##*/}"
      done
    done
  fi
  printf '%s\n' "$dir"
}

# Run the fixture's script once with the ambient PATH and once with no jq on
# PATH, and report the line-1 marker each branch produced. Callers compare the
# two; neither is trusted on its own.
stamp_both_branches() {
  local fixture_dir="$1" stub="$2" body="$3" nojq
  nojq="$(nojq_path)"

  printf '%s' "$body" > "$stub"
  "$fixture_dir/bin/stamp-workflow-versions" >/dev/null 2>&1 || true
  jq_marker="$(head -1 "$stub")"
  jq_status_body="$(cat "$stub")"

  printf '%s' "$body" > "$stub"
  env -i PATH="$nojq" HOME="$HOME" bash "$fixture_dir/bin/stamp-workflow-versions" \
    >/dev/null 2>&1 || true
  nojq_marker="$(head -1 "$stub")"
}

# The pitfall this guards: jq can appear at more than one PATH location, so a
# careless neutralization keeps calling jq and the "no jq" branch is never
# exercised. Assert the neutralization took effect before trusting any result
# that depends on it.
if env -i PATH="$(nojq_path)" HOME="$HOME" bash -c 'command -v jq' >/dev/null 2>&1; then
  fail "the no-jq PATH still resolves jq; the fallback branch was never exercised"
else
  pass "the no-jq PATH resolves no jq, so the fallback branch really runs"
fi
if env -i PATH="$(nojq_path)" HOME="$HOME" bash -c 'command -v awk' >/dev/null 2>&1; then
  pass "the no-jq PATH still provides awk, so the fallback has its parser"
else
  fail "the no-jq PATH lost awk; a failure under it would prove nothing"
fi

# -- the TOP-LEVEL .version is what gets stamped, not the first textual match --
#
# The regression: `grep '"version"' | head -1` chose by position in the FILE. A
# manifest declaring metadata.version before its catalog version stamped every
# stub from the nested value, and --check then accepted that wrong value as
# derived, disabling the drift guard it exists to enforce.
make_fixture "$fixture"
nested_manifest="$fixture/plugins/third-dr/.third-plugin/plugin.json"
stub="$fixture/plugins/third-dr/workflows/publish-third-dr-issue.yml"
cat > "$nested_manifest" <<'JSON'
{
  "name": "third-dr",
  "metadata": {
    "version": "9.9.9"
  },
  "version": "1.2.3"
}
JSON
stamp_both_branches "$fixture" "$stub" 'name: publish
jobs: {}
'
if [[ "$jq_marker" == "$nojq_marker" ]]; then
  pass "both branches agree on a manifest whose nested version precedes the top-level one"
else
  fail "branches disagreed: jq='$jq_marker' no-jq='$nojq_marker'"
fi
if [[ "$jq_marker" == "# third-dr: v1.2.3" ]]; then
  pass "the top-level version is stamped, not the earlier nested metadata.version"
else
  fail "stamped from the wrong field: '$jq_marker' (expected '# third-dr: v1.2.3')"
fi

# Same property under --check: the nested value must not be accepted.
printf '# third-dr: v9.9.9\nname: publish\njobs: {}\n' > "$stub"
if "$fixture/bin/stamp-workflow-versions" --check >/dev/null 2>&1; then
  fail "--check accepted a marker carrying the nested metadata.version"
else
  pass "--check rejects a marker carrying the nested metadata.version"
fi

# -- an absent or non-string top-level version fails loudly --
#
# Failing loudly matters more than the message: a reader that returns empty
# would stamp "# <plugin>: v", and bin/install reads line 1 to detect drift, so
# a blank version silently disables the check for that plugin.
for bad_case in 'absent:{"name": "third-dr", "metadata": {"version": "9.9.9"}}' \
                'number:{"name": "third-dr", "version": 5}' \
                'null:{"name": "third-dr", "version": null}' \
                'object:{"name": "third-dr", "version": {"catalog": "1.0.0"}}'; do
  label="${bad_case%%:*}"
  json="${bad_case#*:}"
  make_fixture "$fixture"
  printf '%s\n' "$json" > "$fixture/plugins/third-dr/.third-plugin/plugin.json"
  stub="$fixture/plugins/third-dr/workflows/publish-third-dr-issue.yml"
  # Start from an UNMARKED stub: make_fixture stamps a correct marker, which
  # would mask a writer that leaves line 1 alone for the wrong reason.
  printf 'name: publish\njobs: {}\n' > "$stub"

  nojq="$(nojq_path)"
  jq_ok=0; nojq_ok=0
  "$fixture/bin/stamp-workflow-versions" >/dev/null 2>&1 && jq_ok=1
  env -i PATH="$nojq" HOME="$HOME" bash "$fixture/bin/stamp-workflow-versions" \
    >/dev/null 2>&1 && nojq_ok=1

  if [[ "$jq_ok" == "$nojq_ok" ]]; then
    pass "both branches agree on a $label top-level version"
  else
    fail "branches disagreed on a $label version: jq_ok=$jq_ok nojq_ok=$nojq_ok"
  fi
  if [[ "$jq_ok" == "0" ]]; then
    pass "a $label top-level version fails the writer instead of stamping a wrong value"
  else
    fail "a $label top-level version was accepted; marker is '$(head -1 "$stub")'"
  fi
  if [[ "$(head -1 "$stub")" == "name: publish" ]]; then
    pass "a $label version leaves the unmarked stub untouched rather than stamping it"
  else
    fail "a $label version still wrote a marker: '$(head -1 "$stub")'"
  fi

  # --check must fail too, rather than reporting the tree as derived.
  if "$fixture/bin/stamp-workflow-versions" --check >/dev/null 2>&1; then
    fail "--check passed a tree whose manifest has a $label top-level version"
  else
    pass "--check fails a tree whose manifest has a $label top-level version"
  fi
done

# -- the branches agree on the real repository's own manifests --
make_fixture "$fixture"
for real_manifest in "$root"/plugins/*/.*-plugin/plugin.json; do
  [[ -e "$real_manifest" ]] || continue
  real_rest="${real_manifest#"$root"/plugins/}"
  real_plugin="${real_rest%%/*}"
  cp "$real_manifest" "$fixture/plugins/third-dr/.third-plugin/plugin.json"
  stub="$fixture/plugins/third-dr/workflows/publish-third-dr-issue.yml"
  stamp_both_branches "$fixture" "$stub" 'name: publish
jobs: {}
'
  if [[ -n "$jq_marker" && "$jq_marker" == "$nojq_marker" ]]; then
    pass "both branches read the same version from $real_plugin's real manifest"
  else
    fail "branches disagreed on $real_plugin: jq='$jq_marker' no-jq='$nojq_marker'"
  fi
done

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
