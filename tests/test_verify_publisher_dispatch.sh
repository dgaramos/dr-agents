#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${VERIFY_SCRIPT:-$root/core/pr-review/scripts/verify-publisher-dispatch.sh}"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# Build a case directory: $1 case name, $2 profile body, remaining args workflow filenames.
make_case() {
  local name="$1" body="$2"; shift 2
  mkdir -p "$temp/$name/workflows"
  printf '%s\n' "$body" >"$temp/$name/PROFILE.md"
  local file
  for file in "$@"; do : >"$temp/$name/workflows/$file"; done
}

run_case() {
  local name="$1"
  set +e
  CASE_STDOUT="$(bash "$script" "$temp/$name/PROFILE.md" "$temp/$name/workflows" 2>"$temp/$name/stderr")"
  CASE_STATUS=$?
  set -e
  CASE_STDERR="$(cat "$temp/$name/stderr")"
}

# --- Reverse direction: installed but never declared. ------------------------
# This is the central case. A forward-only verifier passes it, which is exactly
# how consumer drift stayed undetected.
make_case reverse '- `review`: `.github/workflows/publish-claudio-review.yml`
- `reply`: `.github/workflows/publish-claudio-reply.yml`' \
  publish-claudio-review.yml publish-claudio-reply.yml publish-claudio-pr.yml
run_case reverse
[[ "$CASE_STATUS" == 1 ]] || fail \
  "reverse: publish-claudio-pr.yml is installed and never declared, but the" \
  "verifier exited $CASE_STATUS; the reverse direction is missing"
[[ "$CASE_STDERR" == *"publish-claudio-pr.yml"* ]] ||
  fail "reverse: stderr must name the undeclared file, got: $CASE_STDERR"
[[ "$CASE_STDERR" == *"not declared"* ]] ||
  fail "reverse: stderr must name the direction, got: $CASE_STDERR"

# --- Forward direction: declared but not installed. --------------------------
make_case forward '- `review`: `.github/workflows/publish-cody-review.yml`
- `reply`: `.github/workflows/publish-cody-reply.yml`' \
  publish-cody-review.yml
run_case forward
[[ "$CASE_STATUS" == 1 ]] || fail \
  "forward: publish-cody-reply.yml is declared with no installed file, but the" \
  "verifier exited $CASE_STATUS; the forward direction is missing"
[[ "$CASE_STDERR" == *"publish-cody-reply.yml"* ]] ||
  fail "forward: stderr must name the missing file, got: $CASE_STDERR"
[[ "$CASE_STDERR" == *"not installed"* ]] ||
  fail "forward: stderr must name the direction, got: $CASE_STDERR"

# --- Happy path, prose shape (the catalog's own profile layout). -------------
make_case prose '## Claudio DR publisher modes

- `review`: `.github/workflows/publish-claudio-review.yml`
- `reply`: `.github/workflows/publish-claudio-reply.yml`' \
  publish-claudio-review.yml publish-claudio-reply.yml
run_case prose
[[ "$CASE_STATUS" == 0 ]] || fail "prose: expected exit 0, got $CASE_STATUS ($CASE_STDERR)"
[[ "$CASE_STDOUT" == *"declared: 2"* && "$CASE_STDOUT" == *"installed: 2"* ]] ||
  fail "prose: expected a 2/2 count line, got: $CASE_STDOUT"

# --- Happy path, table shape. Same result, different layout. -----------------
make_case table '| Mode | Claudio DR workflow | Cody DR workflow |
| --- | --- | --- |
| `review` | `publish-claudio-review.yml` | `publish-cody-review.yml` |' \
  publish-claudio-review.yml publish-cody-review.yml
run_case table
[[ "$CASE_STATUS" == 0 ]] || fail "table: expected exit 0, got $CASE_STATUS ($CASE_STDERR)"
[[ "$CASE_STDOUT" == *"declared: 2"* && "$CASE_STDOUT" == *"installed: 2"* ]] ||
  fail "table: expected a 2/2 count line, got: $CASE_STDOUT"

# --- Edge: reusable workflows are not publisher stubs, in either direction. --
# The catalog installs seven `reusable-publish-*.yml` files. A naive glob or an
# unanchored token match reports them as undeclared, or matches the substring
# `publish-review.yml` inside them as a declaration.
make_case reusable '- `review`: `.github/workflows/publish-claudio-review.yml`

The stub calls `.github/workflows/reusable-publish-review.yml`.' \
  publish-claudio-review.yml reusable-publish-review.yml
run_case reusable
[[ "$CASE_STATUS" == 0 ]] || fail "reusable: expected exit 0, got $CASE_STATUS ($CASE_STDERR)"
[[ "$CASE_STDOUT" == *"declared: 1"* && "$CASE_STDOUT" == *"installed: 1"* ]] ||
  fail "reusable: expected a 1/1 count line, got: $CASE_STDOUT"

# --- Edge: a filename that cannot be a stub name is not declarable. ----------
# A valid stub filename never contains a space. Such a file belongs to neither
# direction: it is not reported as undeclared, and it is not counted.
make_case invalid_name '- `comment-issue`: `.github/workflows/publish-claudio-issue-comment.yml`' \
  publish-claudio-issue-comment.yml 'publish-claudio-issue-comment 2.yml'
run_case invalid_name
[[ "$CASE_STATUS" == 0 ]] ||
  fail "invalid_name: expected exit 0, got $CASE_STATUS ($CASE_STDERR)"
[[ "$CASE_STDOUT" == *"declared: 1"* && "$CASE_STDOUT" == *"installed: 1"* ]] ||
  fail "invalid_name: expected a 1/1 count line, got: $CASE_STDOUT"
[[ "$CASE_STDERR" != *"issue-comment 2.yml"* ]] ||
  fail "invalid_name: an invalid stub name must not be reported, got: $CASE_STDERR"

# --- Edge: a filename declared twice counts once. ----------------------------
make_case duplicate '- `review`: `.github/workflows/publish-cody-review.yml`

Reviews dispatch `.github/workflows/publish-cody-review.yml`.' \
  publish-cody-review.yml
run_case duplicate
[[ "$CASE_STATUS" == 0 ]] || fail "duplicate: expected exit 0, got $CASE_STATUS ($CASE_STDERR)"
[[ "$CASE_STDOUT" == *"declared: 1"* ]] ||
  fail "duplicate: a repeated declaration must count once, got: $CASE_STDOUT"

# --- Edge: nothing declared and nothing installed is agreement, not failure. -
make_case empty 'This profile declares no publisher.'
run_case empty
[[ "$CASE_STATUS" == 0 ]] || fail "empty: expected exit 0, got $CASE_STATUS ($CASE_STDERR)"
[[ "$CASE_STDOUT" == *"declared: 0"* && "$CASE_STDOUT" == *"installed: 0"* ]] ||
  fail "empty: expected a 0/0 count line, got: $CASE_STDOUT"

# --- Usage and unreadable input exit 2, distinct from a mismatch. ------------
set +e
bash "$script" >/dev/null 2>&1; status=$?
set -e
[[ "$status" == 2 ]] || fail "usage: expected exit 2 with no arguments, got $status"

set +e
bash "$script" "$temp/absent/PROFILE.md" "$temp/prose/workflows" >/dev/null 2>&1; status=$?
set -e
[[ "$status" == 2 ]] || fail "unreadable profile: expected exit 2, got $status"

set +e
bash "$script" "$temp/prose/PROFILE.md" "$temp/absent-dir" >/dev/null 2>&1; status=$?
set -e
[[ "$status" == 2 ]] || fail "absent workflows dir: expected exit 2, got $status"

# --- The catalog's own profile and installed workflows must agree. -----------
set +e
catalog_stdout="$(bash "$script" "$root/profiles/dr-agents.md" "$root/.github/workflows" 2>&1)"
status=$?
set -e
[[ "$status" == 0 ]] ||
  fail "catalog: profile and installed workflows disagree: $catalog_stdout"

echo "ok: tests/test_verify_publisher_dispatch.sh"
