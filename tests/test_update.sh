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

# dr-agents#455: `agents update --global` is the command every machine uses to
# take a new catalog version, so it is the one that must leave the recorded
# version agreeing with the catalog. `plugin install` no-ops on an
# already-installed plugin; `plugin update` is what re-records.
grep -qF "plugin update claudio-dr@dr-agents" "$claude_call_log" \
  || { echo "FAIL: update did not re-record the claudio-dr version" >&2; exit 1; }

# Re-run against an already-installed plugin recorded at an older version:
# the case the no-op used to leave stale behind a "Global install complete".
stale_version="0.0.1-stale"
stale_path="$claude_dir/plugins/cache/dr-agents/claudio-dr/$stale_version"
mkdir -p "$stale_path/.claude-plugin"
printf '{"name":"claudio-dr","version":"%s"}\n' "$stale_version" \
  > "$stale_path/.claude-plugin/plugin.json"
jq -n --arg path "$stale_path" --arg version "$stale_version" \
  '{version: 2, plugins: {"claudio-dr@dr-agents": [{scope: "user", installPath: $path, version: $version}]}}' \
  > "$claude_dir/plugins/installed_plugins.json"

stale_update_output="$(run_update --global)"
recorded_after="$(jq -r '(.plugins["claudio-dr@dr-agents"] // []) | map(.version // empty) | first // empty' \
  "$claude_dir/plugins/installed_plugins.json")"
[[ "$recorded_after" == "$claudio_ver" ]] \
  || { echo "FAIL: --global left the recorded version at $recorded_after, not $claudio_ver" >&2; exit 1; }
echo "$stale_update_output" | grep -q "Global install complete" \
  || { echo "FAIL: --global did not complete after re-recording; output: $stale_update_output" >&2; exit 1; }
rm -rf "$stale_path"

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

# ---------------------------------------------------------------------------
# Mutually exclusive mode flags
#
# usage() documents --global, --repo and --all as alternative invocations, so no
# two of them may be combined. The argument loop used to be last-wins, which
# silently resolved every pair to whichever flag came last and then executed it
# (dr-agents#299).
#
# These assertions must not be able to pass for an environmental reason. The
# assertion they replace accepted *any* non-zero exit, and a failing
# `git pull --ff-only` supplied one whenever the checkout's branch had no
# configured upstream — so the result was decided by branch configuration
# rather than by bin/update. Each case below therefore asserts the cause and
# not merely the exit status: the message must name both conflicting flags,
# and pull_catalog must never have been reached.
#
# This block owns bin/update's mode-conflict and modifier-guard coverage. It
# moved here from tests/test_update_download.sh when the download route was
# removed (dr-agents#483); the coverage is not download-specific and must not
# disappear with the route.
# ---------------------------------------------------------------------------

# Record git invocations instead of performing them. bin/update runs
# `git pull --ff-only` against its own checkout, which must not happen here,
# and an empty log is the direct evidence that rejection precedes the pull.
readonly conflict_git_log="$tmp/git-conflict.log"
: > "$conflict_git_log"
readonly recording_git="$tmp/recording-bin/git"
mkdir -p "$tmp/recording-bin"
cat > "$recording_git" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "${conflict_git_log}"
exit 0
EOF
chmod +x "$recording_git"
cp "$tmp/bin/codex" "$tmp/recording-bin/codex"
cp "$tmp/bin/claude" "$tmp/recording-bin/claude"

# bin/install --repo installs into the *current working directory*, not into
# HOME, so a faked HOME alone does not contain a stray install: an unrejected
# --repo would write into whatever directory the suite happens to run from,
# which is the catalog checkout itself. Every invocation therefore runs from a
# scratch directory.
readonly conflict_cwd="$tmp/conflict-cwd"
mkdir -p "$conflict_cwd"
readonly conflict_pointer_dir="$fake_home/.local/share/dr-agents"
mkdir -p "$conflict_pointer_dir"

run_update_isolated() {
  ( cd "$conflict_cwd" \
      && HOME="$fake_home" \
         CODEX_CONFIG_DIR="$codex_dir" \
         CLAUDE_CONFIG_DIR="$claude_dir" \
         CODEX_CALL_LOG="$codex_call_log" \
         CLAUDE_CALL_LOG="$claude_call_log" \
         PATH="$tmp/recording-bin:$PATH" \
         bash "$repository_root/bin/update" "$@" 2>&1 )
}

# Sentinel state. A rejected invocation must leave every one of these untouched;
# a silent install is what the last-wins loop actually caused.
echo "sentinel-pointer" > "$conflict_pointer_dir/catalog-path"
rm -rf "$fake_home/.claude" "$claude_dir" "$codex_dir" "$fake_home/.local/bin"

readonly mode_flags=(global repo all)

for first in "${mode_flags[@]}"; do
  for second in "${mode_flags[@]}"; do
    [[ "$first" == "$second" ]] && continue

    if out="$(run_update_isolated "--$first" "--$second" 2>&1)"; then
      echo "FAIL: --$first --$second should be rejected as mutually exclusive, but exited 0; output: $out" >&2
      exit 1
    fi

    if ! echo "$out" | grep -qi "mutually exclusive"; then
      echo "FAIL: --$first --$second exited non-zero, but not for the mutually-exclusive reason; output: $out" >&2
      exit 1
    fi

    if ! echo "$out" | grep -q -- "--$first"; then
      echo "FAIL: rejection of --$first --$second does not name --$first; output: $out" >&2
      exit 1
    fi

    if ! echo "$out" | grep -q -- "--$second"; then
      echo "FAIL: rejection of --$first --$second does not name --$second; output: $out" >&2
      exit 1
    fi

    if echo "$out" | grep -q "Pulling latest catalog"; then
      echo "FAIL: --$first --$second reached pull_catalog before rejecting; the result would then depend on whether the branch has an upstream; output: $out" >&2
      exit 1
    fi
  done
done

# Rejection precedes any git invocation at all, for every pair above.
if [[ -s "$conflict_git_log" ]]; then
  echo "FAIL: a rejected mode pair still invoked git: $(< "$conflict_git_log")" >&2
  exit 1
fi

# No rejected pair installed anything.
pointer_after="$(< "$conflict_pointer_dir/catalog-path")"
[[ "$pointer_after" == "sentinel-pointer" ]] || \
  { echo "FAIL: a rejected mode pair rewrote the catalog-path pointer; got: $pointer_after" >&2; exit 1; }
[[ ! -d "$claude_dir" ]] || \
  { echo "FAIL: a rejected mode pair installed into the Claude config directory" >&2; exit 1; }
[[ ! -d "$codex_dir" ]] || \
  { echo "FAIL: a rejected mode pair installed into the Codex config directory" >&2; exit 1; }
[[ ! -e "$fake_home/.local/bin/agents" ]] || \
  { echo "FAIL: a rejected mode pair installed the agents CLI" >&2; exit 1; }
[[ ! -d "$conflict_cwd/.claude" ]] || \
  { echo "FAIL: a rejected mode pair performed a repo-local install in the working directory" >&2; exit 1; }

# ---------------------------------------------------------------------------
# The modifier guards keep their own messages. These are not mode-versus-mode
# conflicts and must not be absorbed by the mode conflict.
# ---------------------------------------------------------------------------
assert_rejected_with() {
  local expected="$1"; shift
  local output
  if output="$(run_update_isolated "$@" 2>&1)"; then
    echo "FAIL: $* should be rejected; output: $output" >&2
    exit 1
  fi
  echo "$output" | grep -qF -e "$expected" || \
    { echo "FAIL: $* should be rejected with '$expected'; output: $output" >&2; exit 1; }
}

assert_rejected_with "--workflows is only valid with --global" --repo --workflows
assert_rejected_with "--profile is not valid with --global"    --global --profile demo

# ---------------------------------------------------------------------------
# The removed download route (dr-agents#483). `--download` is no longer a mode:
# it must be rejected as an unknown argument before any work happens, not fall
# through to a pull or an install.
# ---------------------------------------------------------------------------
download_out="$(run_update_isolated --download 2>&1 || true)"
if run_update_isolated --download >/dev/null 2>&1; then
  echo "FAIL: bin/update --download should exit non-zero; output: $download_out" >&2
  exit 1
fi
echo "$download_out" | grep -qF "Unknown argument: --download" || \
  { echo "FAIL: bin/update --download should be rejected as an unknown argument; output: $download_out" >&2; exit 1; }
if echo "$download_out" | grep -q "Pulling latest catalog"; then
  echo "FAIL: bin/update --download reached pull_catalog; output: $download_out" >&2
  exit 1
fi

help_out="$(run_update_isolated --help 2>&1 || true)"
if echo "$help_out" | grep -q -- "--download"; then
  echo "FAIL: bin/update --help still documents --download" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# A repeated identical mode flag is not a conflict. Tightening that would be a
# behavior change nobody asked for, so only the absence of the rejection is
# asserted here; the install path itself is covered above.
# ---------------------------------------------------------------------------
repeat_out="$(run_update_isolated --global --global 2>&1 || true)"
if echo "$repeat_out" | grep -qi "mutually exclusive"; then
  echo "FAIL: --global --global is not a mode conflict; output: $repeat_out" >&2
  exit 1
fi

echo "bin/update mode-conflict and download-removal tests passed"
