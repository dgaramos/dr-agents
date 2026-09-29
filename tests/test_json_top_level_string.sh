#!/usr/bin/env bash
# Guards the single top-level-string reading (dr-agents#466 follow-up).
#
# `grep '"version"' … | head -1 | sed …` selects by position in the FILE, not in
# the OBJECT, so a nested `version` ahead of the real one wins. That pipeline had
# been copied five times across bin/install and bin/stamp-workflow-versions.
# Five copies is the reason fixing one instance would not have held, so what is
# guarded here is the single reading, not each call site.
#
# bin/install sources nothing on purpose — `--download` installs it standalone —
# so the reader is necessarily duplicated between the two scripts. That makes
# divergence the live risk, and it is what this file exists to catch: both
# readers are EXTRACTED from the real scripts and run over one shared fixture
# set, and every fixture is also run through both the jq and the no-jq branch of
# each. A reimplementation here would pass while a shipped reader was wrong.
set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
pass() { echo "ok: $*"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A PATH with no jq at all.
#
# A hand-written "clean" PATH is not enough: jq resolves from more than one PATH
# directory on a developer machine, so /usr/bin:/bin still finds it. This
# symlinks every executable name the readers need out of the REAL PATH, omitting
# jq, and then asserts the neutralization took effect before anything trusts it.
readonly nojq_bin="$tmp/nojq-bin"
mkdir -p "$nojq_bin"
for tool in bash awk sed grep head cat printf; do
  resolved="$(command -v "$tool" 2>/dev/null)" || continue
  ln -sf "$resolved" "$nojq_bin/$tool"
done
if PATH="$nojq_bin" command -v jq >/dev/null 2>&1; then
  echo "FAIL: the no-jq PATH still resolves jq; every no-jq result below would be a lie" >&2
  exit 1
fi
PATH="$nojq_bin" command -v awk >/dev/null 2>&1 \
  || { echo "FAIL: the no-jq PATH lost awk, so the fallback cannot run" >&2; exit 1; }
pass "no-jq PATH verified: jq unreachable, awk reachable"

# Extract each reader from its real script into a callable harness.
extract() {
  local src="$1" fn="$2" out="$3"
  awk -v fn="$fn" '
    $0 == fn "() {" { inside = 1 }
    inside { print }
    inside && /^\}$/ { exit }
  ' "$src" > "$out"
  grep -q "^$fn() {\$" "$out" \
    || { echo "FAIL: could not extract $fn from $src" >&2; exit 1; }
  bash -n "$out" || { echo "FAIL: extracted $fn does not parse" >&2; exit 1; }
}

readonly install_reader="$tmp/install-reader.sh"
readonly stamp_reader="$tmp/stamp-reader.sh"
extract bin/install json_top_level_string "$install_reader"
extract bin/stamp-workflow-versions plugin_manifest_version "$stamp_reader"
pass "both readers extracted from the shipped scripts and parse"

# bin/stamp-workflow-versions' reader takes a plugin name and globs its manifest,
# so it is driven through a fixture tree rather than a bare file.
readonly plugin_tree="$tmp/tree"
mkdir -p "$plugin_tree/plugins/p-dr/.x-plugin" "$plugin_tree/plugins/p-dr/workflows"

cat > "$tmp/run-install.sh" <<'HARNESS'
set -uo pipefail
source "$1"
json_top_level_string version "$2"
HARNESS
cat > "$tmp/run-stamp.sh" <<'HARNESS'
set -uo pipefail
cd "$1"
source "$2"
plugin_manifest_version p-dr
HARNESS

# One fixture set, four readings each: {install, stamp} x {jq, no-jq}.
# Expected values are stated independently of every parser.
check_fixture() {
  local name="$1" json="$2" expected="$3"
  printf '%s' "$json" > "$tmp/one.json"
  printf '%s' "$json" > "$plugin_tree/plugins/p-dr/.x-plugin/plugin.json"

  local a b c d
  a="$(bash "$tmp/run-install.sh" "$install_reader" "$tmp/one.json" 2>/dev/null || true)"
  b="$(env PATH="$nojq_bin" bash "$tmp/run-install.sh" "$install_reader" "$tmp/one.json" 2>/dev/null || true)"
  c="$(bash "$tmp/run-stamp.sh" "$plugin_tree" "$stamp_reader" 2>/dev/null || true)"
  d="$(env PATH="$nojq_bin" bash "$tmp/run-stamp.sh" "$plugin_tree" "$stamp_reader" 2>/dev/null || true)"

  if [[ "$a" != "$b" ]]; then
    fail "$name: bin/install jq and no-jq branches disagree ('$a' vs '$b')"; return
  fi
  if [[ "$c" != "$d" ]]; then
    fail "$name: bin/stamp-workflow-versions jq and no-jq branches disagree ('$c' vs '$d')"; return
  fi
  if [[ "$a" != "$c" ]]; then
    fail "$name: the two scripts' readers disagree ('$a' vs '$c')"; return
  fi
  if [[ "$a" != "$expected" ]]; then
    fail "$name: expected '${expected:-<none>}', all readers returned '${a:-<none>}'"; return
  fi
  pass "$name -> ${a:-<nothing>}"
}

# The defect that started this: a nested version ahead of the real one.
check_fixture "nested metadata.version first" \
  '{"name":"p","metadata":{"version":"9.9.9"},"version":"1.2.3"}' "1.2.3"
check_fixture "version nested two levels deep first" \
  '{"a":{"b":{"version":"8.8.8"}},"version":"2.0.0"}' "2.0.0"
check_fixture "version inside an array of objects" \
  '{"deps":[{"version":"7.7.7"}],"version":"3.0.0"}' "3.0.0"
check_fixture "nested block, then array, then top level" \
  '{"agents":{"version":"1.1.1"},"x":[1,2],"version":"7.0.0"}' "7.0.0"
check_fixture "pretty-printed, nested first" \
  '{
  "metadata": { "version": "9.9.9" },
  "version": "8.0.0"
}' "8.0.0"

# A string value that contains the key spelling. An escape-blind scanner reads
# the decoy; both readers must not.
check_fixture "escaped quotes forming a decoy in a string" \
  '{"desc":"a \"version\": \"0.0.0\" trap","version":"6.0.0"}' "6.0.0"
check_fixture "a brace inside a string value" \
  '{"desc":"an unbalanced { brace","version":"6.5.0"}' "6.5.0"

# A longer key that merely contains the field name must not match.
check_fixture "schemaVersion before version" \
  '{"schemaVersion":"6.6.6","version":"5.0.0"}' "5.0.0"
check_fixture "a key whose name ends in the field" \
  '{"pluginversion":"4.4.4","version":"5.5.0"}' "5.5.0"

# Absent, or present but not a string: nothing, not a wrong value. A blank here
# would stamp `# <plugin>: v` and silently disable the installer's drift check.
check_fixture "top level only" '{"version":"4.0.0"}' "4.0.0"
check_fixture "no version anywhere" '{"name":"p"}' ""
check_fixture "top-level version is a number" '{"version":123}' ""
check_fixture "top-level version is null" '{"version":null}' ""
check_fixture "top-level version is an object" '{"version":{"major":1}}' ""
check_fixture "top-level version is an array" '{"version":["1.0.0"]}' ""
check_fixture "only a nested version exists" '{"metadata":{"version":"9.9.9"}}' ""

# The reader must return non-zero on the empty cases, because callers branch on
# its status and not only on its output.
printf '%s' '{"name":"p"}' > "$tmp/one.json"
if bash "$tmp/run-install.sh" "$install_reader" "$tmp/one.json" >/dev/null 2>&1; then
  fail "bin/install's reader exits zero when the field is absent"
else
  pass "bin/install's reader exits non-zero when the field is absent"
fi

# The real manifests must read identically through both scripts and both
# branches — the values every stub marker and the installer's gate depend on.
for spec in "claudio-dr:.claude-plugin" "cody-dr:.codex-plugin"; do
  plugin="${spec%%:*}"; mdir="${spec##*:}"
  manifest="plugins/$plugin/$mdir/plugin.json"
  real_jq="$(bash "$tmp/run-install.sh" "$install_reader" "$manifest" 2>/dev/null || true)"
  real_nojq="$(env PATH="$nojq_bin" bash "$tmp/run-install.sh" "$install_reader" "$manifest" 2>/dev/null || true)"
  if [[ -n "$real_jq" && "$real_jq" == "$real_nojq" ]]; then
    pass "$manifest reads as $real_jq under both branches"
  else
    fail "$manifest: jq='$real_jq' no-jq='$real_nojq'"
  fi
done

# The copies this change removed must not come back. The reader's own comment
# quotes the defective pipeline, so only executable lines are considered.
strays="$(grep -nE "grep +'\"(version|tag_name)\"'" bin/install bin/stamp-workflow-versions \
  | grep -v '^\s*#' | grep -vE ':[0-9]+:#' || true)"
if [[ -z "$strays" ]]; then
  pass "no line-matching version pipeline remains in either script"
else
  fail "a line-matching version pipeline came back:"$'\n'"$strays"
fi

if [[ "$failures" -gt 0 ]]; then
  echo "$failures assertion(s) failed" >&2
  exit 1
fi
echo "top-level string reader tests passed"
