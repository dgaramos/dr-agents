#!/usr/bin/env bash
# dr-agents#457: every assertion in bin/check that can fail must name the file
# and the expectation. Before this test, ~70 bare `grep -q` / `jq -e` call sites
# exited non-zero having printed nothing at all, and the only way to find the
# cause was `bash -x bin/check 2>&1 | tail -20`.
#
# The coverage is provided structurally by an ERR trap rather than by ~70
# per-site messages, so this test pins the two properties that trap depends on:
# it fires, and it fires INSIDE FUNCTIONS (which requires `errtrace`).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT

check="$root/bin/check"
marker='bin/check: assertion failed'

# --- 1. The trap is installed and errtrace is enabled. -----------------------
#
# Asserted on the source text because a missing `-E` does not break anything
# visibly: it silently reduces coverage to top-level assertions only. Without
# this assertion, deleting the `E` would leave every test in the suite green.
if ! grep -q '^set -Eeuo pipefail$' "$check"; then
  echo "bin/check must enable errtrace (set -Eeuo pipefail) so the ERR trap" >&2
  echo "  is inherited by shell functions; without it, assertions inside" >&2
  echo "  functions fail silently" >&2
  exit 1
fi
if ! grep -q "trap .*$marker.*ERR" "$check"; then
  echo "bin/check must install an ERR trap naming the failing assertion" >&2
  exit 1
fi

# --- 2. Failure path: a broken manifest names the file. ---------------------
#
# AC-02: a deliberately broken plugins/cody-dr/.codex-plugin/plugin.json must
# produce a message naming that file before bin/check exits non-zero.
fixture="$temp/repo"
mkdir -p "$fixture"
tar -cf - -C "$root" --exclude .git --exclude .dr-agents . | tar -xf - -C "$fixture"
jq '.name = "wrong-name"' \
  "$root/plugins/cody-dr/.codex-plugin/plugin.json" \
  >"$fixture/plugins/cody-dr/.codex-plugin/plugin.json"

set +e
(cd "$fixture" && bash bin/check >"$temp/out" 2>"$temp/err")
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  echo "a broken Cody manifest must fail bin/check" >&2
  exit 1
fi
if ! grep -q 'plugins/cody-dr/.codex-plugin/plugin.json' "$temp/err"; then
  echo "bin/check must name plugins/cody-dr/.codex-plugin/plugin.json when its" >&2
  echo "  manifest assertion fails; stderr was:" >&2
  tail -5 "$temp/err" >&2
  exit 1
fi

# --- 3. Edge case: an assertion inside a function is still named. -----------
#
# This is the case a trap without `errtrace` misses. The preamble is extracted
# from bin/check itself rather than retyped, so the fixture cannot drift away
# from what the gate actually does.
{
  sed -n '1,/^trap .*ERR$/p' "$check"
  cat <<'EOF'
some_validator() {
  grep -qF 'string-that-is-not-in-the-target' "$1"
}
some_validator "$1"
echo "UNREACHABLE"
EOF
} >"$temp/fn.sh"
# Deliberately an empty, separate file: pointing the fixture at its own source
# makes the search string match itself and the assertion passes for the wrong
# reason.
: >"$temp/fn.target"

set +e
bash "$temp/fn.sh" "$temp/fn.target" >"$temp/fn.out" 2>"$temp/fn.err"
fn_status=$?
set -e

if [[ "$fn_status" -eq 0 ]] || grep -q UNREACHABLE "$temp/fn.out"; then
  echo "a failing assertion inside a function must abort" >&2
  exit 1
fi
if ! grep -q "$marker" "$temp/fn.err"; then
  echo "a failing assertion inside a function must print a named message;" >&2
  echo "  this is the case that requires errtrace. stderr was:" >&2
  cat "$temp/fn.err" >&2
  exit 1
fi
if ! grep -q 'string-that-is-not-in-the-target' "$temp/fn.err"; then
  echo "the message must quote the failing command" >&2
  cat "$temp/fn.err" >&2
  exit 1
fi

# --- 4. Happy path: a healthy tree stays quiet. -----------------------------
#
# bin/check writes expected stderr noise from the negative tests it runs, so
# this asserts the absence of the trap marker specifically, not an empty
# stderr. A trap that fires on a passing gate would be worse than the silence
# it replaces.
set +e
(cd "$root" && bash bin/check >"$temp/ok.out" 2>"$temp/ok.err")
ok_status=$?
set -e

if [[ "$ok_status" -ne 0 ]]; then
  echo "bin/check must pass on the unmodified tree" >&2
  tail -5 "$temp/ok.err" >&2
  exit 1
fi
if grep -q "$marker" "$temp/ok.err"; then
  echo "the ERR trap must not fire on a passing gate; it did:" >&2
  grep "$marker" "$temp/ok.err" >&2
  exit 1
fi

echo "bin/check assertion message tests passed"
