#!/usr/bin/env bash
set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

readonly fake_home="$tmp/home"
readonly fake_repo="$tmp/repo"
readonly codex_dir="$tmp/home/.codex"
readonly fake_git="$tmp/bin/git"
readonly codex_call_log="$tmp/codex.log"

mkdir -p "$fake_home" "$fake_repo" "$tmp/bin"

# Stub git: records calls, succeeds silently for pull --ff-only
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
cp "$repository_root/tests/helpers/fake-codex.sh" "$tmp/bin/codex"
chmod +x "$tmp/bin/codex"

run_update() {
  GIT_CALL_LOG="$tmp/git.log" \
  HOME="$fake_home" \
  CODEX_CONFIG_DIR="$codex_dir" \
  CODEX_CALL_LOG="$codex_call_log" \
  PATH="$tmp/bin:$PATH" \
    bash "$repository_root/bin/update" "$@" 2>&1
}

# ---------------------------------------------------------------------------
# --global: pulls catalog then installs globally
# ---------------------------------------------------------------------------
run_update --global >/dev/null

cody_ver="$(jq -r '.version' "$repository_root/plugins/cody-dr/.codex-plugin/plugin.json" 2>/dev/null \
  || grep '"version"' "$repository_root/plugins/cody-dr/.codex-plugin/plugin.json" | head -1 \
  | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"

grep -qF "pull --ff-only" "$tmp/git.log" || { echo "FAIL: git pull not called" >&2; exit 1; }
[[ -f "$fake_home/.claude/.claude-plugin/plugin.json" ]] || { echo "FAIL: claudio-dr not installed" >&2; exit 1; }
[[ -f "$codex_dir/plugins/cache/dr-agents/cody-dr/${cody_ver}/.codex-plugin/plugin.json" ]] || { echo "FAIL: cody-dr not installed" >&2; exit 1; }
[[ ! -e "$codex_dir/plugins/cache/cody-dr" ]] || { echo "FAIL: update created the legacy direct Cody cache" >&2; exit 1; }
grep -qF "plugin add cody-dr@dr-agents" "$codex_call_log" || { echo "FAIL: update did not refresh cody-dr@dr-agents" >&2; exit 1; }

# ---------------------------------------------------------------------------
# --repo: pulls catalog then installs repo-local
# ---------------------------------------------------------------------------
rm -f "$tmp/git.log"
(cd "$fake_repo" && run_update --repo >/dev/null)

grep -qF "pull --ff-only" "$tmp/git.log" || { echo "FAIL: git pull not called for --repo" >&2; exit 1; }
[[ -f "$fake_repo/.claude/.claude-plugin/plugin.json" ]] || { echo "FAIL: repo claudio-dr not installed" >&2; exit 1; }

# ---------------------------------------------------------------------------
# --repo --profile: applies named profile after pull
# ---------------------------------------------------------------------------
rm -f "$tmp/git.log"
(cd "$fake_repo" && run_update --repo --profile dr-agents >/dev/null)

[[ -f "$fake_repo/.claude/profiles/dr-agents.md" ]] || { echo "FAIL: profile not applied" >&2; exit 1; }

# ---------------------------------------------------------------------------
# --all: pulls once, installs global + repo when .claude/ exists
# ---------------------------------------------------------------------------
rm -rf "$fake_home/.claude" "$codex_dir" "$fake_repo/.claude"
rm -f "$tmp/git.log"

mkdir -p "$fake_repo/.claude"
(cd "$fake_repo" && run_update --all >/dev/null)

pull_count="$(grep -c "pull --ff-only" "$tmp/git.log")"
[[ "$pull_count" -eq 1 ]] || { echo "FAIL: expected 1 git pull, got $pull_count" >&2; exit 1; }
[[ -f "$fake_home/.claude/.claude-plugin/plugin.json" ]]  || { echo "FAIL: --all: claudio-dr global not installed" >&2; exit 1; }
[[ -f "$fake_repo/.claude/.claude-plugin/plugin.json" ]]  || { echo "FAIL: --all: claudio-dr repo not installed" >&2; exit 1; }

# ---------------------------------------------------------------------------
# --all: skips repo install when .claude/ does not exist in CWD
# ---------------------------------------------------------------------------
rm -rf "$fake_home/.claude" "$codex_dir" "$fake_repo/.claude"
rm -f "$tmp/git.log"

output="$(cd "$fake_repo" && run_update --all 2>&1)"
echo "$output" | grep -q "skipping repo update" || { echo "FAIL: expected skip message when no .claude/" >&2; exit 1; }
[[ ! -d "$fake_repo/.claude" ]] || { echo "FAIL: .claude/ should not be created by --all with no prior repo install" >&2; exit 1; }

# ---------------------------------------------------------------------------
# bad args: no mode exits non-zero
# ---------------------------------------------------------------------------
if run_update 2>/dev/null; then
  echo "FAIL: expected usage error with no args, got success" >&2
  exit 1
fi

# --profile with --global exits non-zero
if run_update --global --profile dr-agents 2>/dev/null; then
  echo "FAIL: expected error for --profile with --global, got success" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# --global --force: forwards --force to bin/install and overwrites conflicts
# ---------------------------------------------------------------------------
rm -rf "$fake_home/.claude" "$codex_dir"
run_update --global >/dev/null 2>&1

echo "tampered" > "$fake_home/.claude/.claude-plugin/plugin.json"
force_output="$(run_update --global --force 2>&1)"
echo "$force_output" | grep -q "WARNING" || { echo "FAIL: --global --force should print WARNING for overwritten file" >&2; exit 1; }
actual="$(< "$fake_home/.claude/.claude-plugin/plugin.json")"
expected="$(< "$repository_root/plugins/claudio-dr/.claude-plugin/plugin.json")"
[[ "$actual" == "$expected" ]] || { echo "FAIL: --global --force did not overwrite the tampered file" >&2; exit 1; }

# ---------------------------------------------------------------------------
# --repo --force: forwards --force to bin/install
# ---------------------------------------------------------------------------
rm -rf "$fake_repo/.claude"
(cd "$fake_repo" && run_update --repo >/dev/null 2>&1)
echo "tampered" > "$fake_repo/.claude/.claude-plugin/plugin.json"
repo_force_output="$(cd "$fake_repo" && run_update --repo --force 2>&1)"
echo "$repo_force_output" | grep -q "WARNING" || { echo "FAIL: --repo --force should print WARNING" >&2; exit 1; }
repo_actual="$(< "$fake_repo/.claude/.claude-plugin/plugin.json")"
repo_expected="$(< "$repository_root/plugins/claudio-dr/.claude-plugin/plugin.json")"
[[ "$repo_actual" == "$repo_expected" ]] || { echo "FAIL: --repo --force did not overwrite the tampered file" >&2; exit 1; }

echo "bin/update tests passed"
