#!/usr/bin/env bash
# tests/test_install_vendored_core.sh — the installer rejects vendored core/ files
#
# A catalog file copied into a consumer at the catalog's own path is a copy
# nothing installs, verifies, or removes (dr-agents#304). Both consumers that
# carried one drifted; a third never received it. The check mode of bin/install
# is the consumer-facing gate, so it must turn red while naming the file and
# its state — an identical copy is the same defect as a diverged one, because
# identical today does not stay identical.
set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

readonly fake_home="$tmp/home"
readonly helper_rel="core/issue-workflow/scripts/apply-pr-metadata.sh"
mkdir -p "$fake_home"

[[ -f "$repository_root/$helper_rel" ]] \
  || { echo "FAIL: fixture assumption broken: catalog lacks $helper_rel" >&2; exit 1; }

# Each case gets a fresh consumer with a current stub set so the only variable
# under test is the vendored file.
new_consumer() {
  local dir="$tmp/$1"
  mkdir -p "$dir/.github/workflows"
  for src in "$repository_root"/plugins/claudio-dr/workflows/publish-*.yml \
             "$repository_root"/plugins/cody-dr/workflows/publish-*.yml; do
    cp "$src" "$dir/.github/workflows/"
  done
  printf '%s' "$dir"
}

run_check() {
  local dir="$1"; shift
  (cd "$dir" && HOME="$fake_home" bash "$repository_root/bin/install" "$@" 2>&1)
}

expect_pass() {
  local dir="$1" description="$2" output
  output="$(run_check "$dir")" \
    || { echo "FAIL: check mode rejected $description" >&2; echo "$output" >&2; exit 1; }
  grep -q 'vendored catalog file' <<<"$output" \
    && { echo "FAIL: check mode reported a vendored file for $description" >&2; echo "$output" >&2; exit 1; }
  return 0
}

expect_reject() {
  local dir="$1" description="$2" state="$3" output
  if output="$(run_check "$dir")"; then
    echo "FAIL: check mode accepted $description" >&2; echo "$output" >&2; exit 1
  fi
  grep -qF "vendored catalog file: ${helper_rel} (${state}" <<<"$output" \
    || { echo "FAIL: rejection of $description does not name ${helper_rel} as ${state}" >&2
         echo "$output" >&2; exit 1; }
}

# Happy path — a consumer with no root core/ passes and reports nothing.
expect_pass "$(new_consumer clean)" "a consumer without core/"

# Failure — a copy that diverged from the catalog names the file and the state.
diverged="$(new_consumer diverged)"
mkdir -p "$(dirname "$diverged/$helper_rel")"
{ cat "$repository_root/$helper_rel"; echo "# local edit"; } >"$diverged/$helper_rel"
expect_reject "$diverged" "a diverged vendored copy" "diverged"

# Failure — a byte-identical copy is the same defect class: nothing verifies it.
identical="$(new_consumer identical)"
mkdir -p "$(dirname "$identical/$helper_rel")"
cp "$repository_root/$helper_rel" "$identical/$helper_rel"
expect_reject "$identical" "an identical vendored copy" "identical"

# Edge — a root core/ that the consumer owns (no catalog counterpart) is not ours.
owned="$(new_consumer owned)"
mkdir -p "$owned/core"
echo "consumer content" >"$owned/core/unrelated.txt"
expect_pass "$owned" "a consumer-owned core/ file with no catalog counterpart"

# Edge — nested core/ trees are ordinary source directories, never vendoring.
nested="$(new_consumer nested)"
mkdir -p "$nested/apps/x/$(dirname "$helper_rel")"
cp "$repository_root/$helper_rel" "$nested/apps/x/$helper_rel"
expect_pass "$nested" "a nested core/ tree"

# Workflow install must report the same defect, so a consumer is not skipped by
# the path it happened to take (bin/update --global --workflows delegates here).
target="$(new_consumer install-mode)"
mkdir -p "$(dirname "$target/$helper_rel")"
cp "$repository_root/$helper_rel" "$target/$helper_rel"
if output="$(run_check "$target" --workflows)"; then
  echo "FAIL: --workflows accepted an identical vendored copy" >&2; echo "$output" >&2; exit 1
fi
grep -qF "vendored catalog file: ${helper_rel} (identical" <<<"$output" \
  || { echo "FAIL: --workflows did not name ${helper_rel}" >&2; echo "$output" >&2; exit 1; }
grep -q 'unchanged  publish-claudio-pr-metadata.yml' <<<"$output" \
  || { echo "FAIL: --workflows must still process stubs before reporting vendored files" >&2; echo "$output" >&2; exit 1; }

echo "PASS: bin/install rejects vendored core/ files by name and state"
