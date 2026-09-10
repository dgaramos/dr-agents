#!/usr/bin/env bash
# tests/test_update_workflows.sh — tests for agents update --global --workflows
set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

readonly fake_home="$tmp/home"
readonly fake_repo="$tmp/repo"
readonly codex_dir="$tmp/home/.codex"
readonly fake_git="$tmp/bin/git"

mkdir -p "$fake_home" "$fake_repo" "$tmp/bin"

cat > "$fake_git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GIT_CALL_LOG"
if [[ "$*" == *"pull --ff-only"* ]]; then
  echo "Already up to date."
  exit 0
fi
exec /usr/bin/git "$@"
EOF
chmod +x "$fake_git"

run_update() {
  GIT_CALL_LOG="$tmp/git.log" \
  HOME="$fake_home" \
  CODEX_CONFIG_DIR="$codex_dir" \
  PATH="$tmp/bin:$PATH" \
    bash "$repository_root/bin/update" "$@" 2>&1
}

claudio_ver="$(grep '"version"' "$repository_root/plugins/claudio-dr/.claude-plugin/plugin.json" | head -1 \
  | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"

mkdir -p "$fake_repo/.github/workflows"

# ---------------------------------------------------------------------------
# Criterion 4a — drifted workflow gets updated
# ---------------------------------------------------------------------------
echo "# claudio-dr: v0.0.1" > "$fake_repo/.github/workflows/publish-claudio-issue.yml"
echo "name: drifted" >> "$fake_repo/.github/workflows/publish-claudio-issue.yml"

update_output="$(cd "$fake_repo" && run_update --global --workflows 2>&1)"
echo "$update_output" | grep -q "updated" \
  || { echo "FAIL: agents update --global --workflows should report 'updated' for drifted file" >&2
       echo "Output was: $update_output" >&2; exit 1; }
grep -qF "# claudio-dr: v${claudio_ver}" "$fake_repo/.github/workflows/publish-claudio-issue.yml" \
  || { echo "FAIL: drifted workflow not updated to current version" >&2; exit 1; }

# bin/update delegates workflow installation to bin/install --workflows, so the
# no-vendoring guarantee of dr-agents#260 T09 must hold through this path too.
# Asserting it here rather than trusting the delegation keeps the guarantee
# attached to the command an operator actually runs on a migrated repository.
[[ ! -e "$fake_repo/.github/scripts" ]] \
  || { echo "FAIL: --global --workflows must not vendor publication scripts into the consumer" >&2
       ls -R "$fake_repo/.github/scripts" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Criterion 4b — current workflow reports unchanged
# ---------------------------------------------------------------------------
rm -f "$tmp/git.log"
unchanged_output="$(cd "$fake_repo" && run_update --global --workflows 2>&1)"
unchanged_output_no_absent="$(echo "$unchanged_output" | grep "publish-claudio-issue" || true)"
# The already-updated file should not be reported as 'updated' again;
# it should be 'unchanged' or 'present'.
# Accept either 'unchanged' or 'present' — both are valid for a current file.
if echo "$unchanged_output" | grep "publish-claudio-issue" | grep -qE "updated"; then
  echo "FAIL: --global --workflows should not report 'updated' for already-current file" >&2
  echo "Output was: $unchanged_output" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Criterion 4c — --global --workflows --force overwrites regardless of version
# ---------------------------------------------------------------------------
rm -f "$tmp/git.log"
force_output="$(cd "$fake_repo" && run_update --global --workflows --force 2>&1)"
echo "$force_output" | grep -q "installed\|updated" \
  || { echo "FAIL: --global --workflows --force should report installed/updated" >&2
       echo "Output was: $force_output" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Criterion 4d — git pull is called
# ---------------------------------------------------------------------------
grep -qF "pull --ff-only" "$tmp/git.log" \
  || { echo "FAIL: git pull --ff-only not called by --global --workflows" >&2; exit 1; }

echo "bin/update workflow tests passed"
