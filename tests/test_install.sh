#!/usr/bin/env bash
set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

readonly fake_home="$tmp/home"
readonly fake_repo="$tmp/repo"
readonly codex_dir="$tmp/home/.codex"

# Run bin/install with overridden HOME and CODEX_CONFIG_DIR.
# First arg is the working directory; remaining args are passed to bin/install.
# The first argument is the working directory to run from. bin/install --repo
# installs into the current working directory rather than into HOME, so this
# must actually take effect: without it an unrejected --repo writes into
# whatever directory the suite runs from, which is the catalog checkout.
run_install() {
  local workdir="$1"; shift
  ( cd "$workdir" \
      && HOME="$fake_home" CODEX_CONFIG_DIR="$codex_dir" \
         bash "$repository_root/bin/install" "$@" 2>&1 )
}

mkdir -p "$fake_home" "$fake_repo"

# ---------------------------------------------------------------------------
# --global: installs claudio-dr and cody-dr into simulated home directories
# ---------------------------------------------------------------------------
run_install "$tmp" --global

claudio_manifest="$fake_home/.claude/.claude-plugin/plugin.json"
cody_ver="$(jq -r '.version' "$repository_root/plugins/cody-dr/.codex-plugin/plugin.json" 2>/dev/null \
  || grep '"version"' "$repository_root/plugins/cody-dr/.codex-plugin/plugin.json" | head -1 \
  | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
cody_manifest="$codex_dir/plugins/cache/cody-dr/${cody_ver}/.codex-plugin/plugin.json"

agents_bin="$fake_home/.local/bin/agents"

[[ -f "$claudio_manifest" ]] || { echo "FAIL: claudio-dr plugin.json not installed" >&2; exit 1; }
[[ -f "$cody_manifest" ]]    || { echo "FAIL: cody-dr plugin.json not installed" >&2; exit 1; }
[[ -f "$agents_bin" ]]       || { echo "FAIL: agents CLI not installed at $agents_bin" >&2; exit 1; }
[[ -x "$agents_bin" ]]       || { echo "FAIL: agents CLI is not executable" >&2; exit 1; }
# The wrapper reads the pointer file at runtime; verify it references the pointer file path.
grep -q "catalog-path" "$agents_bin" || { echo "FAIL: agents wrapper does not reference pointer file (catalog-path)" >&2; exit 1; }

global_pointer="$fake_home/.local/share/dr-agents/catalog-path"
[[ -f "$global_pointer" ]] || { echo "FAIL: --global did not write pointer file at $global_pointer" >&2; exit 1; }
pointer_content="$(< "$global_pointer")"
[[ -n "$pointer_content" ]] || { echo "FAIL: --global wrote an empty pointer file" >&2; exit 1; }

# ---------------------------------------------------------------------------
# --global: re-run on unchanged files is clean (no conflict)
# ---------------------------------------------------------------------------
run_install "$tmp" --global

# ---------------------------------------------------------------------------
# --global: conflict detected when an existing file differs
# ---------------------------------------------------------------------------
echo "tampered" > "$claudio_manifest"
if run_install "$tmp" --global; then
  echo "FAIL: expected conflict exit on tampered file, got success" >&2
  exit 1
fi

# restore for subsequent tests
rm -rf "$fake_home/.claude"

# ---------------------------------------------------------------------------
# --repo: installs claudio-dr into a local .claude/ directory
# ---------------------------------------------------------------------------
(cd "$fake_repo" && HOME="$fake_home" CODEX_CONFIG_DIR="$codex_dir" bash "$repository_root/bin/install" --repo >/dev/null)

repo_manifest="$fake_repo/.claude/.claude-plugin/plugin.json"
[[ -f "$repo_manifest" ]] || { echo "FAIL: repo claudio-dr plugin.json not installed" >&2; exit 1; }

repo_pointer="$fake_home/.local/share/dr-agents/catalog-path"
[[ -f "$repo_pointer" ]] || { echo "FAIL: --repo did not write pointer file at $repo_pointer" >&2; exit 1; }
repo_pointer_content="$(< "$repo_pointer")"
[[ -n "$repo_pointer_content" ]] || { echo "FAIL: --repo wrote an empty pointer file" >&2; exit 1; }

# ---------------------------------------------------------------------------
# --repo --profile: copies the named profile file
# ---------------------------------------------------------------------------
(cd "$fake_repo" && HOME="$fake_home" CODEX_CONFIG_DIR="$codex_dir" bash "$repository_root/bin/install" --repo --profile dr-agents >/dev/null)

profile_dest="$fake_repo/.claude/profiles/dr-agents.md"
[[ -f "$profile_dest" ]] || { echo "FAIL: profile not installed at $profile_dest" >&2; exit 1; }

# ---------------------------------------------------------------------------
# --repo --profile: unknown profile exits non-zero
# ---------------------------------------------------------------------------
if (cd "$fake_repo" && HOME="$fake_home" CODEX_CONFIG_DIR="$codex_dir" bash "$repository_root/bin/install" --repo --profile no-such-profile 2>/dev/null); then
  echo "FAIL: expected failure for unknown profile, got success" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# --status: runs without error and reports both plugins
# ---------------------------------------------------------------------------
status_output="$(cd "$fake_repo" && HOME="$fake_home" CODEX_CONFIG_DIR="$codex_dir" bash "$repository_root/bin/install" --status 2>&1)"
echo "$status_output" | grep -q "claudio-dr" || { echo "FAIL: status output missing claudio-dr" >&2; exit 1; }
echo "$status_output" | grep -q "cody-dr"    || { echo "FAIL: status output missing cody-dr" >&2; exit 1; }
echo "$status_output" | grep -q "agents"     || { echo "FAIL: status output missing agents" >&2; exit 1; }

# ---------------------------------------------------------------------------
# no args: reports workflow check (no longer a usage error)
# ---------------------------------------------------------------------------
noargs_output="$(cd "$fake_repo" && run_install "$fake_repo")"
echo "$noargs_output" | grep -qE "absent|present|drifted|Workflow status" \
  || { echo "FAIL: no-args should report workflow status" >&2; exit 1; }

# --profile without --repo exits non-zero
if run_install "$tmp" --profile dr-agents 2>/dev/null; then
  echo "FAIL: expected error for --profile without --repo, got success" >&2
  exit 1
fi

# --force with --status exits non-zero
if run_install "$tmp" --status --force 2>/dev/null; then
  echo "FAIL: expected error for --force with --status, got success" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# --global --force: overwrites a tampered file and prints a warning
# ---------------------------------------------------------------------------
run_install "$tmp" --global >/dev/null 2>&1 || true
echo "tampered" > "$fake_home/.claude/.claude-plugin/plugin.json"

force_output="$(run_install "$tmp" --global --force 2>&1)"
if [[ $? -ne 0 ]]; then
  echo "FAIL: --global --force should exit 0 even on content difference" >&2
  exit 1
fi
echo "$force_output" | grep -q "WARNING" || { echo "FAIL: --force should print a warning for overwritten file" >&2; exit 1; }
actual="$(< "$fake_home/.claude/.claude-plugin/plugin.json")"
expected="$(< "$repository_root/plugins/claudio-dr/.claude-plugin/plugin.json")"
[[ "$actual" == "$expected" ]] || { echo "FAIL: --force did not overwrite the tampered file with catalog content" >&2; exit 1; }

rm -rf "$fake_home/.claude"

# ---------------------------------------------------------------------------
# --global --force: identical files are skipped silently (no WARNING, no error)
# ---------------------------------------------------------------------------
run_install "$tmp" --global >/dev/null 2>&1

force_clean_output="$(run_install "$tmp" --global --force 2>&1)"
echo "$force_clean_output" | grep -q "already current" || { echo "FAIL: --force on identical files should print 'already current'" >&2; exit 1; }
if echo "$force_clean_output" | grep -q "^  WARNING"; then
  echo "FAIL: --force should not print WARNING for identical files" >&2; exit 1
fi

rm -rf "$fake_home/.claude"

# ---------------------------------------------------------------------------
# --repo --force: overwrites a tampered file and exits 0
# ---------------------------------------------------------------------------
(cd "$fake_repo" && HOME="$fake_home" CODEX_CONFIG_DIR="$codex_dir" bash "$repository_root/bin/install" --repo >/dev/null 2>&1)
echo "tampered" > "$fake_repo/.claude/.claude-plugin/plugin.json"

repo_force_output="$(cd "$fake_repo" && HOME="$fake_home" CODEX_CONFIG_DIR="$codex_dir" bash "$repository_root/bin/install" --repo --force 2>&1)"
[[ $? -eq 0 ]] || true  # captured above; verify via content
echo "$repo_force_output" | grep -q "WARNING" || { echo "FAIL: --repo --force should print WARNING" >&2; exit 1; }
repo_actual="$(< "$fake_repo/.claude/.claude-plugin/plugin.json")"
repo_expected="$(< "$repository_root/plugins/claudio-dr/.claude-plugin/plugin.json")"
[[ "$repo_actual" == "$repo_expected" ]] || { echo "FAIL: --repo --force did not overwrite the tampered file" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Mutually exclusive mode flags
#
# --global, --repo, --download, --status and --workflows are five alternative
# invocations in usage(); no two may be combined. The argument loop was
# last-wins, so a pair was silently resolved to whichever flag came last and
# then executed — `bin/install --global --download` performed a download-based
# install. This is the same defect fixed in bin/update for dr-agents#299, and
# bin/install is reached directly through `agents install`.
#
# Each case asserts the cause, not just a non-zero exit, so that an unrelated
# failure cannot satisfy it.
# ---------------------------------------------------------------------------
readonly install_scratch="$tmp/install-scratch"
mkdir -p "$install_scratch"
rm -rf "$fake_home/.claude" "$codex_dir" "$fake_home/.local"

readonly install_mode_flags=(global repo download status workflows)

for first in "${install_mode_flags[@]}"; do
  for second in "${install_mode_flags[@]}"; do
    [[ "$first" == "$second" ]] && continue

    if out="$(run_install "$install_scratch" "--$first" "--$second" 2>&1)"; then
      echo "FAIL: bin/install --$first --$second should be rejected as mutually exclusive, but exited 0; output: $out" >&2
      exit 1
    fi

    if ! echo "$out" | grep -qi "mutually exclusive"; then
      echo "FAIL: bin/install --$first --$second exited non-zero, but not for the mutually-exclusive reason; output: $out" >&2
      exit 1
    fi

    if ! echo "$out" | grep -q -- "--$first"; then
      echo "FAIL: rejection of bin/install --$first --$second does not name --$first; output: $out" >&2
      exit 1
    fi

    if ! echo "$out" | grep -q -- "--$second"; then
      echo "FAIL: rejection of bin/install --$first --$second does not name --$second; output: $out" >&2
      exit 1
    fi
  done
done

# No rejected pair installed anything.
[[ ! -d "$fake_home/.claude" ]] || \
  { echo "FAIL: a rejected bin/install mode pair installed into ~/.claude" >&2; exit 1; }
[[ ! -d "$codex_dir" ]] || \
  { echo "FAIL: a rejected bin/install mode pair installed into the Codex config directory" >&2; exit 1; }
[[ ! -e "$fake_home/.local/bin/agents" ]] || \
  { echo "FAIL: a rejected bin/install mode pair installed the agents CLI" >&2; exit 1; }
[[ ! -d "$install_scratch/.claude" ]] || \
  { echo "FAIL: a rejected bin/install mode pair performed a repo-local install" >&2; exit 1; }

# A repeated identical mode flag is not a conflict.
install_repeat_out="$(run_install "$install_scratch" --status --status 2>&1 || true)"
if echo "$install_repeat_out" | grep -qi "mutually exclusive"; then
  echo "FAIL: bin/install --status --status is not a mode conflict; output: $install_repeat_out" >&2
  exit 1
fi

echo "bin/install tests passed"
