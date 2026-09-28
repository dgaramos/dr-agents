#!/usr/bin/env bash
# Guards the guarded-invocation detector from dr-agents#457.
#
# bash suppresses `set -e` through the entire body of a function invoked in a
# guarded context, so bare assertions inside it stop aborting. Every such
# function in bin/check is currently called unguarded, which means the real tree
# proves nothing here -- a detector that never fires and a detector that cannot
# fire look identical against a healthy repository. These fixtures make it fire.
set -euo pipefail

readonly repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# The detector is extracted from bin/check rather than reimplemented. A copy
# would pass while the shipped block was wrong -- the reasoning
# tests/test_stub_version_guard.sh already records for the stub detector.
sed -n '/^guarded_assertion_calls() {/,/^}$/p' "$repo_root/bin/check" > "$tmp/detector.sh"
[[ -s "$tmp/detector.sh" ]] || fail "could not extract guarded_assertion_calls from bin/check"
# shellcheck disable=SC1090
source "$tmp/detector.sh"

probe() {
  printf '%s\n' "$@" > "$tmp/probe.sh"
  guarded_assertion_calls "$tmp/probe.sh"
}

# --- unguarded invocation is the healthy shape ------------------------------
out="$(probe 'validate_thing() {' '  grep -q x y' '}' 'validate_thing .')"
[[ -z "$out" ]] || fail "an unguarded invocation was reported as guarded: $out"
echo "ok   accepts an unguarded invocation"

# --- the four guarded shapes ------------------------------------------------
for guarded in \
  'validate_thing . || echo fallback' \
  'if validate_thing .; then :; fi' \
  'validate_thing . && echo next' \
  '! validate_thing .'; do
  out="$(probe 'validate_thing() {' '  grep -q x y' '}' "$guarded")"
  [[ -n "$out" ]] || fail "a guarded invocation was not reported: $guarded"
  grep -qF "validate_thing" <<<"$out" || fail "the report must name the function; got: $out"
done
echo "ok   reports each guarded invocation shape"

# --- a comment mentioning the call is not a call ----------------------------
# The detector's own explanatory comment in bin/check contains the exact text
# `validate_surface_metadata . || echo "..."`. Matching it would make bin/check
# fail on itself, and the fix would be to delete the explanation.
out="$(probe 'validate_thing() {' '  grep -q x y' '}' '# validate_thing . || echo "in a comment"')"
[[ -z "$out" ]] || fail "a comment was reported as a call site: $out"
echo "ok   ignores a comment that mentions a guarded call"

# --- derived, not enumerated ------------------------------------------------
# A function no list mentions must still be covered, by prefix alone.
out="$(probe 'assert_never_mentioned_anywhere() {' '  grep -q x y' '}' 'assert_never_mentioned_anywhere . || true')"
grep -qF "assert_never_mentioned_anywhere" <<<"$out" \
  || fail "a function absent from every list must still be covered; got: $out"
echo "ok   covers a function no list in bin/check mentions"

# --- the repository's own tree must be clean --------------------------------
out="$(guarded_assertion_calls "$repo_root/bin/check")"
[[ -z "$out" ]] || fail "bin/check has a guarded assertion call site: $out"
echo "ok   the repository's own bin/check has none"

echo "PASS: $(basename "${BASH_SOURCE[0]}")"
