#!/usr/bin/env bash
set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly script="$repository_root/core/profile-discovery/scripts/discover-project-profile.sh"
readonly temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

fail() {
  echo "$1" >&2
  exit 1
}

# Each case runs against its own scratch root so one placement cannot leak into
# the next. The previous version of this file reused a single root and grew it,
# which is why no near-miss case existed: every placement after the first one
# already had an accepted profile.
new_root() {
  mktemp -d "$temporary_directory/root.XXXXXX"
}

# Captures stdout, stderr and the status separately. The distinction this file
# exists to test is precisely that they differ, so a helper that merges the two
# streams cannot assert it.
run_discovery() {
  local root="$1"
  set +e
  discovery_stdout="$("$script" --root "$root" 2>"$temporary_directory/stderr")"
  discovery_status=$?
  set -e
  discovery_stderr="$(cat "$temporary_directory/stderr")"
}

# --- accepted: one profile at the canonical depth -----------------------------
root="$(new_root)"
mkdir -p "$root/.dr-agents/example"
touch "$root/.dr-agents/example/PROFILE.md"
run_discovery "$root"
[[ $discovery_status -eq 0 ]] || fail "accepted profile must exit 0"
[[ "$discovery_stdout" == "$root/.dr-agents/example/PROFILE.md" ]] ||
  fail "accepted profile must print its path"
[[ -z "$discovery_stderr" ]] || fail "accepted profile must not warn"

# An accepted profile alongside a near miss still reports only the accepted
# path, and reports it as a clean success: the repository is working.
root="$(new_root)"
mkdir -p "$root/.dr-agents/example"
touch "$root/.dr-agents/example/PROFILE.md"
touch "$root/.dr-agents/PROFILE.md"
run_discovery "$root"
[[ $discovery_status -eq 0 ]] || fail "accepted profile must win over a candidate"
[[ "$discovery_stdout" == "$root/.dr-agents/example/PROFILE.md" ]] ||
  fail "accepted profile must print its path even with a rejected candidate"

# --- genuine absence: no .dr-agents directory at all --------------------------
root="$(new_root)"
run_discovery "$root"
[[ $discovery_status -eq 0 ]] || fail "genuine absence must exit 0"
[[ -z "$discovery_stdout" ]] || fail "genuine absence must print nothing on stdout"
[[ -z "$discovery_stderr" ]] || fail "genuine absence must be silent on stderr"

# An empty .dr-agents directory holds nothing profile-shaped, so it is still a
# genuine absence rather than a near miss.
root="$(new_root)"
mkdir -p "$root/.dr-agents/example"
touch "$root/.dr-agents/example/README.md"
run_discovery "$root"
[[ $discovery_status -eq 0 ]] || fail "unrelated files must exit 0"
[[ -z "$discovery_stdout$discovery_stderr" ]] ||
  fail "unrelated files under .dr-agents must stay silent"

# --- rejected candidates inside .dr-agents: exit 4, named, with a reason ------
assert_rejected_inside() {
  local root="$1" candidate="$2" reason="$3"
  run_discovery "$root"
  [[ $discovery_status -eq 4 ]] ||
    fail "candidate $candidate must exit 4, got $discovery_status"
  [[ -z "$discovery_stdout" ]] ||
    fail "candidate $candidate must not print a path on stdout"
  [[ "$discovery_stderr" == *"rejected project profile candidates"* ]] ||
    fail "candidate $candidate must name the outcome on stderr"
  [[ "$discovery_stderr" == *"$candidate"* ]] ||
    fail "candidate $candidate must be named on stderr"
  [[ "$discovery_stderr" == *"$reason"* ]] ||
    fail "candidate $candidate must state the reason '$reason'"
}

root="$(new_root)"
touch "$root/.dr-agents/PROFILE.md" 2>/dev/null || { mkdir -p "$root/.dr-agents"; touch "$root/.dr-agents/PROFILE.md"; }
assert_rejected_inside "$root" "$root/.dr-agents/PROFILE.md" "not nested in a project directory"

root="$(new_root)"
mkdir -p "$root/.dr-agents/a/b"
touch "$root/.dr-agents/a/b/PROFILE.md"
assert_rejected_inside "$root" "$root/.dr-agents/a/b/PROFILE.md" "nested too deeply"

root="$(new_root)"
mkdir -p "$root/.dr-agents/proj"
touch "$root/.dr-agents/proj/profile.md"
assert_rejected_inside "$root" "$root/.dr-agents/proj/profile.md" "filename case does not match PROFILE.md"

root="$(new_root)"
mkdir -p "$root/.dr-agents/proj"
touch "$root/.dr-agents/proj/Profile.md"
assert_rejected_inside "$root" "$root/.dr-agents/proj/Profile.md" "filename case does not match PROFILE.md"

# Several rejected candidates are all named, not just the first.
root="$(new_root)"
mkdir -p "$root/.dr-agents/proj" "$root/.dr-agents/a/b"
touch "$root/.dr-agents/proj/profile.md" "$root/.dr-agents/a/b/PROFILE.md"
run_discovery "$root"
[[ $discovery_status -eq 4 ]] || fail "multiple candidates must exit 4"
[[ "$discovery_stderr" == *"$root/.dr-agents/proj/profile.md"* &&
   "$discovery_stderr" == *"$root/.dr-agents/a/b/PROFILE.md"* ]] ||
  fail "every rejected candidate must be named"

# --- rejected candidate at the repository root: advisory, still exit 0 --------
# A file inside .dr-agents/ is unambiguously meant as a profile. A PROFILE.md at
# the repository root is not: it is an ordinary filename in projects unrelated
# to this catalog, so promoting it to a non-zero status would fail discovery for
# repositories that are working correctly. It is reported, not enforced.
root="$(new_root)"
touch "$root/PROFILE.md"
run_discovery "$root"
[[ $discovery_status -eq 0 ]] ||
  fail "a root PROFILE.md must not fail discovery, got $discovery_status"
[[ -z "$discovery_stdout" ]] || fail "a root PROFILE.md must not reach stdout"
[[ "$discovery_stderr" == *"$root/PROFILE.md"* ]] ||
  fail "a root PROFILE.md must be named on stderr"
[[ "$discovery_stderr" == *"outside .dr-agents/"* ]] ||
  fail "a root PROFILE.md must state why it was rejected"

# The root advisory must still be distinguishable from a genuine absence, which
# is the acceptance criterion for this placement.
[[ -n "$discovery_stderr" ]] || fail "a root PROFILE.md must be distinguishable from absence"

# A candidate inside .dr-agents/ decides the status even when a root candidate
# is also present.
root="$(new_root)"
mkdir -p "$root/.dr-agents/proj"
touch "$root/PROFILE.md" "$root/.dr-agents/proj/profile.md"
run_discovery "$root"
[[ $discovery_status -eq 4 ]] || fail "an inside candidate must dominate the root advisory"
[[ "$discovery_stderr" == *"$root/PROFILE.md"* ]] ||
  fail "the root candidate must still be reported"

# --- ambiguity: unchanged ----------------------------------------------------
root="$(new_root)"
mkdir -p "$root/.dr-agents/first" "$root/.dr-agents/second"
touch "$root/.dr-agents/first/PROFILE.md" "$root/.dr-agents/second/PROFILE.md"
run_discovery "$root"
[[ $discovery_status -eq 3 ]] || fail "two accepted profiles must exit 3"
[[ "$discovery_stderr" == *"ambiguous project profiles"* ]] ||
  fail "ambiguity must keep its message"
[[ -z "$discovery_stdout" ]] || fail "ambiguity must not print a path"

# --- usage errors: unchanged -------------------------------------------------
run_discovery_argv() {
  set +e
  "$script" "$@" >/dev/null 2>&1
  discovery_status=$?
  set -e
}
run_discovery_argv --root
[[ $discovery_status -eq 64 ]] || fail "--root without a value must exit 64"
run_discovery_argv --root "$temporary_directory" extra
[[ $discovery_status -eq 64 ]] || fail "an extra argument must exit 64"

echo "ok"
