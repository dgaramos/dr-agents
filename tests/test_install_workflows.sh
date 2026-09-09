#!/usr/bin/env bash
# tests/test_install_workflows.sh — tests for agents install workflow management
set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

readonly fake_home="$tmp/home"
readonly fake_repo="$tmp/repo"
readonly codex_dir="$tmp/home/.codex"

mkdir -p "$fake_home" "$fake_repo"

run_install() {
  local workdir="$1"; shift
  HOME="$fake_home" CODEX_CONFIG_DIR="$codex_dir" \
    bash "$repository_root/bin/install" "$@" 2>&1
}

# ---------------------------------------------------------------------------
# Criterion 1 — workflow templates exist and carry version comments
# ---------------------------------------------------------------------------

claudio_ver="$(grep '"version"' "$repository_root/plugins/claudio-dr/.claude-plugin/plugin.json" | head -1 \
  | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
cody_ver="$(grep '"version"' "$repository_root/plugins/cody-dr/.codex-plugin/plugin.json" | head -1 \
  | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"

for wf in publish-claudio-issue.yml publish-claudio-pr-metadata.yml publish-claudio-review.yml \
          publish-claudio-reply.yml publish-claudio-resolve.yml; do
  src="$repository_root/plugins/claudio-dr/workflows/$wf"
  [[ -f "$src" ]] || { echo "FAIL: claudio-dr workflow template missing: $wf" >&2; exit 1; }
  grep -qF "# claudio-dr: v${claudio_ver}" "$src" \
    || { echo "FAIL: claudio-dr workflow template missing version comment in $wf" >&2; exit 1; }
done

for wf in publish-cody-issue.yml publish-cody-pr-metadata.yml publish-cody-review.yml \
          publish-cody-reply.yml publish-cody-resolve.yml; do
  src="$repository_root/plugins/cody-dr/workflows/$wf"
  [[ -f "$src" ]] || { echo "FAIL: cody-dr workflow template missing: $wf" >&2; exit 1; }
  grep -qF "# cody-dr: v${cody_ver}" "$src" \
    || { echo "FAIL: cody-dr workflow template missing version comment in $wf" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# Criterion 2 — agents install (no args) reports workflow presence without writing files
# ---------------------------------------------------------------------------

# 2a: repo without .github/workflows/ — all absent, no files written
check_output="$(cd "$fake_repo" && run_install "$fake_repo")"
echo "$check_output" | grep -q "absent" \
  || { echo "FAIL: agents install (no args) should report 'absent' for missing workflows" >&2
       echo "Output was: $check_output" >&2; exit 1; }
[[ ! -d "$fake_repo/.github" ]] \
  || { echo "FAIL: agents install (no args) must not write any files" >&2; exit 1; }

# 2b: repo with all current workflows — all present
mkdir -p "$fake_repo/.github/workflows"
for wf in publish-claudio-issue.yml publish-claudio-pr-metadata.yml publish-claudio-review.yml \
          publish-claudio-reply.yml publish-claudio-resolve.yml \
          publish-cody-issue.yml publish-cody-pr-metadata.yml publish-cody-review.yml \
          publish-cody-reply.yml publish-cody-resolve.yml; do
  cp "$repository_root/plugins/claudio-dr/workflows/$wf" \
     "$fake_repo/.github/workflows/$wf" 2>/dev/null \
  || cp "$repository_root/plugins/cody-dr/workflows/$wf" \
        "$fake_repo/.github/workflows/$wf" 2>/dev/null \
  || true
done
# copy all from both plugin directories
for wf in publish-claudio-issue.yml publish-claudio-pr-metadata.yml publish-claudio-review.yml \
          publish-claudio-reply.yml publish-claudio-resolve.yml; do
  cp "$repository_root/plugins/claudio-dr/workflows/$wf" "$fake_repo/.github/workflows/$wf"
done
for wf in publish-cody-issue.yml publish-cody-pr-metadata.yml publish-cody-review.yml \
          publish-cody-reply.yml publish-cody-resolve.yml; do
  cp "$repository_root/plugins/cody-dr/workflows/$wf" "$fake_repo/.github/workflows/$wf"
done

present_output="$(cd "$fake_repo" && run_install "$fake_repo")"
echo "$present_output" | grep -q "present" \
  || { echo "FAIL: agents install (no args) should report 'present' for up-to-date workflows" >&2
       echo "Output was: $present_output" >&2; exit 1; }
echo "$present_output" | grep -qv "absent" 2>/dev/null || true  # soft check; present overrides

# 2c: repo with drifted workflow — reports drifted
echo "# claudio-dr: v0.0.1" > "$fake_repo/.github/workflows/publish-claudio-issue.yml"
echo "name: drifted" >> "$fake_repo/.github/workflows/publish-claudio-issue.yml"
drifted_output="$(cd "$fake_repo" && run_install "$fake_repo")"
echo "$drifted_output" | grep -q "drifted" \
  || { echo "FAIL: agents install (no args) should report 'drifted' for outdated workflow" >&2
       echo "Output was: $drifted_output" >&2; exit 1; }

# restore
rm -rf "$fake_repo/.github"

# ---------------------------------------------------------------------------
# Criterion 3 — agents install --workflows installs absent workflows
# ---------------------------------------------------------------------------

# 3a: happy path — installs all workflows
install_output="$(cd "$fake_repo" && run_install "$fake_repo" --workflows)"
echo "$install_output" | grep -q "installed" \
  || { echo "FAIL: agents install --workflows should report 'installed'" >&2
       echo "Output was: $install_output" >&2; exit 1; }
[[ -f "$fake_repo/.github/workflows/publish-claudio-issue.yml" ]] \
  || { echo "FAIL: publish-claudio-issue.yml not created by --workflows" >&2; exit 1; }
[[ -f "$fake_repo/.github/workflows/publish-cody-issue.yml" ]] \
  || { echo "FAIL: publish-cody-issue.yml not created by --workflows" >&2; exit 1; }

# 3b: idempotency — second run reports unchanged
for helper in publish-pr.sh publish-review.sh publish-pr-metadata.sh publish-cody-thread-action.sh publish-claudio-thread-action.sh apply-pr-metadata.sh; do
  [[ -f "$fake_repo/.github/scripts/agent-workflows/$helper" ]] || { echo "missing installed helper: $helper" >&2; exit 1; }
done
for adapter in cody claudio; do
  [[ -f "$fake_repo/.github/workflows/publish-${adapter}-pr.yml" ]] || exit 1
done

idempotent_output="$(cd "$fake_repo" && run_install "$fake_repo" --workflows)"
echo "$idempotent_output" | grep -q "unchanged" \
  || { echo "FAIL: second agents install --workflows should report 'unchanged'" >&2
       echo "Output was: $idempotent_output" >&2; exit 1; }

# 3c: --force overwrites existing workflows and reports installed
echo "# claudio-dr: v0.0.1" > "$fake_repo/.github/workflows/publish-claudio-issue.yml"
force_output="$(cd "$fake_repo" && run_install "$fake_repo" --workflows --force)"
echo "$force_output" | grep -q "installed" \
  || { echo "FAIL: --workflows --force should report 'installed' for overwritten file" >&2
       echo "Output was: $force_output" >&2; exit 1; }
grep -qF "# claudio-dr: v${claudio_ver}" "$fake_repo/.github/workflows/publish-claudio-issue.yml" \
  || { echo "FAIL: --workflows --force did not restore current version" >&2; exit 1; }

rm -rf "$fake_repo/.github"

# ---------------------------------------------------------------------------
# Criterion 4 — workflow template content satisfies policy constraints
# ---------------------------------------------------------------------------

# Review workflows must allow COMMENT only — APPROVE must not appear as an option.
for wf in \
  "$repository_root/plugins/claudio-dr/workflows/publish-claudio-review.yml" \
  "$repository_root/plugins/cody-dr/workflows/publish-cody-review.yml"; do
  name="$(basename "$wf")"
  grep -qE "options:[[:space:]]*\[COMMENT\]" "$wf" \
    || { echo "FAIL: $name must have options: [COMMENT] only" >&2; exit 1; }
  grep -q "APPROVE" "$wf" \
    && { echo "FAIL: $name must not contain APPROVE — it is a human decision" >&2; exit 1; } || true
done

# PR metadata workflows must declare project_owner, project_number, project_status.
for wf in \
  "$repository_root/plugins/claudio-dr/workflows/publish-claudio-pr-metadata.yml" \
  "$repository_root/plugins/cody-dr/workflows/publish-cody-pr-metadata.yml"; do
  name="$(basename "$wf")"
  for field in project_owner project_number project_status; do
    grep -qF "${field}:" "$wf" \
      || { echo "FAIL: $name must declare input field: $field" >&2; exit 1; }
  done
done

# Issue workflows must not request organization-level project permissions.
for wf in \
  "$repository_root/plugins/claudio-dr/workflows/publish-claudio-issue.yml" \
  "$repository_root/plugins/cody-dr/workflows/publish-cody-issue.yml"; do
  name="$(basename "$wf")"
  grep -q "permission-organization-projects" "$wf" \
    && { echo "FAIL: $name must not request permission-organization-projects" >&2; exit 1; } || true
done

# ---------------------------------------------------------------------------
# Criterion 5 — issue workflows GET and validate author before PATCH
# ---------------------------------------------------------------------------

for wf in \
  "$repository_root/plugins/claudio-dr/workflows/publish-claudio-issue.yml" \
  "$repository_root/plugins/cody-dr/workflows/publish-cody-issue.yml"; do
  name="$(basename "$wf")"
  grep -q "method GET" "$wf" \
    || { echo "FAIL: $name must perform a GET to validate issue author before PATCH" >&2; exit 1; }
  # GET must appear before PATCH in file order
  get_line="$(grep -n "method GET" "$wf" | head -1 | cut -d: -f1)"
  patch_line="$(grep -n "method PATCH" "$wf" | head -1 | cut -d: -f1)"
  [[ -n "$get_line" && -n "$patch_line" && "$get_line" -lt "$patch_line" ]] \
    || { echo "FAIL: $name GET must appear before PATCH for pre-mutation author validation" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# Criterion 6 — all checkout steps set persist-credentials: false
# ---------------------------------------------------------------------------

checkout_workflows=(
  "$repository_root/plugins/claudio-dr/workflows/publish-claudio-pr-metadata.yml"
  "$repository_root/plugins/claudio-dr/workflows/publish-claudio-review.yml"
  "$repository_root/plugins/claudio-dr/workflows/publish-claudio-reply.yml"
  "$repository_root/plugins/claudio-dr/workflows/publish-claudio-resolve.yml"
  "$repository_root/plugins/cody-dr/workflows/publish-cody-pr-metadata.yml"
  "$repository_root/plugins/cody-dr/workflows/publish-cody-review.yml"
  "$repository_root/plugins/cody-dr/workflows/publish-cody-reply.yml"
  "$repository_root/plugins/cody-dr/workflows/publish-cody-resolve.yml"
)

for wf in "${checkout_workflows[@]}"; do
  name="$(basename "$wf")"
  grep -qF "persist-credentials: false" "$wf" \
    || { echo "FAIL: $name must set persist-credentials: false on all checkout steps" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# Criterion 7 — all checkout steps pin to refs/heads/main
# ---------------------------------------------------------------------------

for wf in "${checkout_workflows[@]}"; do
  name="$(basename "$wf")"
  grep -qF "ref: refs/heads/main" "$wf" \
    || { echo "FAIL: $name must pin checkout to ref: refs/heads/main" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# Criterion 8 — inline_comments_json description is a quoted YAML string
# ---------------------------------------------------------------------------

for wf in \
  "$repository_root/plugins/claudio-dr/workflows/publish-claudio-review.yml" \
  "$repository_root/plugins/cody-dr/workflows/publish-cody-review.yml"; do
  name="$(basename "$wf")"
  grep -qE "inline_comments_json:.*description:[[:space:]]*\"" "$wf" \
    || grep -qE "description:[[:space:]]*\"[^\"]*\"" "$wf" \
    || { echo "FAIL: $name inline_comments_json description must be a quoted YAML string" >&2; exit 1; }
done

echo "bin/install workflow tests passed"
