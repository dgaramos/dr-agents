#!/usr/bin/env bash
set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

readonly fake_home="$tmp/home"
readonly fake_repo="$tmp/repo"
readonly codex_dir="$tmp/home/.codex"
readonly claude_dir="$tmp/home/.claude"
readonly fake_git="$tmp/bin/git"
readonly codex_call_log="$tmp/codex.log"
readonly claude_call_log="$tmp/claude.log"

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
cp "$repository_root/tests/helpers/fake-claude.sh" "$tmp/bin/claude"
chmod +x "$tmp/bin/codex" "$tmp/bin/claude"
for stub in claude codex; do
  resolved="$(PATH="$tmp/bin:$PATH" command -v "$stub")"
  [[ "$resolved" == "$tmp/bin/$stub" ]] \
    || { echo "FAIL: PATH resolves $stub to $resolved, not the fake" >&2; exit 1; }
done

run_update() {
  GIT_CALL_LOG="$tmp/git.log" \
  HOME="$fake_home" \
  CODEX_CONFIG_DIR="$codex_dir" \
  CLAUDE_CONFIG_DIR="$claude_dir" \
  CODEX_CALL_LOG="$codex_call_log" \
  CLAUDE_CALL_LOG="$claude_call_log" \
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
claudio_ver="$(jq -r '.version' "$repository_root/plugins/claudio-dr/.claude-plugin/plugin.json")"
[[ -f "$claude_dir/plugins/cache/dr-agents/claudio-dr/${claudio_ver}/.claude-plugin/plugin.json" ]] || { echo "FAIL: claudio-dr not installed" >&2; exit 1; }
[[ -f "$codex_dir/plugins/cache/dr-agents/cody-dr/${cody_ver}/.codex-plugin/plugin.json" ]] || { echo "FAIL: cody-dr not installed" >&2; exit 1; }
[[ ! -e "$codex_dir/plugins/cache/cody-dr" ]] || { echo "FAIL: update created the legacy direct Cody cache" >&2; exit 1; }
[[ ! -e "$claude_dir/.claude-plugin/plugin.json" ]] || { echo "FAIL: update created the legacy direct Claudio copy" >&2; exit 1; }
grep -qF "plugin add cody-dr@dr-agents" "$codex_call_log" || { echo "FAIL: update did not refresh cody-dr@dr-agents" >&2; exit 1; }
grep -qF "plugin install claudio-dr@dr-agents" "$claude_call_log" || { echo "FAIL: update did not refresh claudio-dr@dr-agents" >&2; exit 1; }

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
rm -rf "$fake_home/.claude" "$claude_dir" "$codex_dir" "$fake_repo/.claude"
rm -f "$tmp/git.log"

mkdir -p "$fake_repo/.claude"
(cd "$fake_repo" && run_update --all >/dev/null)

pull_count="$(grep -c "pull --ff-only" "$tmp/git.log")"
[[ "$pull_count" -eq 1 ]] || { echo "FAIL: expected 1 git pull, got $pull_count" >&2; exit 1; }
[[ -f "$claude_dir/plugins/cache/dr-agents/claudio-dr/${claudio_ver}/.claude-plugin/plugin.json" ]]  || { echo "FAIL: --all: claudio-dr global not installed" >&2; exit 1; }
[[ -f "$fake_repo/.claude/.claude-plugin/plugin.json" ]]  || { echo "FAIL: --all: claudio-dr repo not installed" >&2; exit 1; }

# ---------------------------------------------------------------------------
# --all: skips repo install when .claude/ does not exist in CWD
# ---------------------------------------------------------------------------
rm -rf "$fake_home/.claude" "$claude_dir" "$codex_dir" "$fake_repo/.claude"
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
# --global --force: accepted, and still routes through the marketplaces
#
# dr-agents#427 removed the direct plugin copy that --force used to overwrite
# under --global, so there is no longer a conflicting file for it to resolve
# there. --force forwarding through install_plugin_dir is asserted by the
# --repo --force case below, which is now the mode that copies files. What
# --global must still guarantee is that --force neither fails nor resurrects a
# direct copy as a "forced" shortcut past the marketplace.
#
# dr-agents#433: it must also carry the marketplace snapshot refresh all the way
# through the update. bin/install's own suite asserts the refresh fires there;
# this asserts it survives the update -> install hop, which is the path an
# operator actually runs and the only one where a stale snapshot can undo the
# pull that just happened.
# ---------------------------------------------------------------------------
rm -rf "$fake_home/.claude" "$claude_dir" "$codex_dir"
: > "$claude_call_log"
: > "$codex_call_log"
run_update --global --force >/dev/null 2>&1 \
  || { echo "FAIL: --global --force should exit 0" >&2; exit 1; }

grep -qF "plugin install claudio-dr@dr-agents" "$claude_call_log" \
  || { echo "FAIL: --global --force did not install claudio-dr@dr-agents" >&2; exit 1; }
grep -qF "plugin marketplace update dr-agents" "$claude_call_log" \
  || { echo "FAIL: --global --force did not refresh the Claude marketplace snapshot" >&2; exit 1; }
grep -qF "plugin marketplace upgrade dr-agents" "$codex_call_log" \
  || { echo "FAIL: --global --force did not refresh the Codex marketplace snapshot" >&2; exit 1; }
[[ ! -e "$claude_dir/.claude-plugin/plugin.json" ]] \
  || { echo "FAIL: --global --force created the legacy direct Claudio copy" >&2; exit 1; }

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
