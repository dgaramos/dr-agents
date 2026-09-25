#!/usr/bin/env bash
set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

readonly fake_home="$tmp/home"
readonly fake_repo="$tmp/repo"
readonly codex_dir="$tmp/home/.codex"
readonly claude_dir="$tmp/home/.claude"
readonly fake_bin="$tmp/bin"
readonly codex_call_log="$tmp/codex.log"
readonly claude_call_log="$tmp/claude.log"

# Run bin/install with overridden HOME and CODEX_CONFIG_DIR.
# First arg is the working directory; remaining args are passed to bin/install.
# The first argument is the working directory to run from. bin/install --repo
# installs into the current working directory rather than into HOME, so this
# must actually take effect: without it an unrejected --repo writes into
# whatever directory the suite runs from, which is the catalog checkout.
run_install() {
  local workdir="$1"; shift
  ( cd "$workdir" \
      && HOME="$fake_home" CODEX_CONFIG_DIR="$codex_dir" CLAUDE_CONFIG_DIR="$claude_dir" \
         CODEX_CALL_LOG="$codex_call_log" CLAUDE_CALL_LOG="$claude_call_log" \
         PATH="$fake_bin:$PATH" \
         bash "$repository_root/bin/install" "$@" 2>&1 )
}

mkdir -p "$fake_home" "$fake_repo" "$fake_bin"
cp "$repository_root/tests/helpers/fake-codex.sh" "$fake_bin/codex"
cp "$repository_root/tests/helpers/fake-claude.sh" "$fake_bin/claude"
chmod +x "$fake_bin/codex" "$fake_bin/claude"

# The fakes must actually shadow the real CLIs. A suite that silently invoked
# the real `claude` would mutate the developer's own ~/.claude — the exact
# state dr-agents#427 exists to stop duplicating. Assert the resolution before
# asserting anything about the fakes.
for stub in claude codex; do
  resolved="$(PATH="$fake_bin:$PATH" command -v "$stub")"
  [[ "$resolved" == "$fake_bin/$stub" ]] \
    || { echo "FAIL: PATH resolves $stub to $resolved, not the fake at $fake_bin/$stub" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# --global: installs claudio-dr and cody-dr into simulated home directories
# ---------------------------------------------------------------------------
run_install "$tmp" --global

claudio_ver="$(jq -r '.version' "$repository_root/plugins/claudio-dr/.claude-plugin/plugin.json")"
claudio_manifest="$claude_dir/plugins/cache/dr-agents/claudio-dr/${claudio_ver}/.claude-plugin/plugin.json"
cody_ver="$(jq -r '.version' "$repository_root/plugins/cody-dr/.codex-plugin/plugin.json" 2>/dev/null \
  || grep '"version"' "$repository_root/plugins/cody-dr/.codex-plugin/plugin.json" | head -1 \
  | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
cody_manifest="$codex_dir/plugins/cache/dr-agents/cody-dr/${cody_ver}/.codex-plugin/plugin.json"

agents_bin="$fake_home/.local/bin/agents"

[[ -f "$claudio_manifest" ]] || { echo "FAIL: claudio-dr plugin.json not installed" >&2; exit 1; }
[[ -f "$cody_manifest" ]]    || { echo "FAIL: cody-dr plugin.json not installed" >&2; exit 1; }
[[ ! -e "$codex_dir/plugins/cache/cody-dr" ]] \
  || { echo "FAIL: --global created the legacy direct Cody cache" >&2; exit 1; }
# dr-agents#427: --global must not recreate the legacy direct Claudio payload.
[[ ! -e "$claude_dir/.claude-plugin/plugin.json" ]] \
  || { echo "FAIL: --global created the legacy direct Claudio payload copy" >&2; exit 1; }
for legacy in agents skills core references hooks scripts; do
  [[ ! -e "$claude_dir/$legacy" ]] \
    || { echo "FAIL: --global created the legacy direct Claudio payload at $claude_dir/$legacy" >&2; exit 1; }
done
grep -qF "plugin marketplace add $repository_root" "$codex_call_log" \
  || { echo "FAIL: --global did not register the dr-agents marketplace" >&2; exit 1; }
grep -qF "plugin add cody-dr@dr-agents" "$codex_call_log" \
  || { echo "FAIL: --global did not install cody-dr@dr-agents" >&2; exit 1; }
grep -qF "plugin marketplace add $repository_root" "$claude_call_log" \
  || { echo "FAIL: --global did not register the dr-agents Claude marketplace" >&2; exit 1; }
grep -qF "plugin install claudio-dr@dr-agents" "$claude_call_log" \
  || { echo "FAIL: --global did not install claudio-dr@dr-agents" >&2; exit 1; }
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
# --global: a pre-existing legacy direct copy is reported, not removed
#
# dr-agents#427. Conflict safety already left such a file alone, but silently:
# nothing told the operator that a second, drifting installation existed. The
# report is the new behavior; leaving the file in place is asserted alongside
# it so a future "helpful" cleanup cannot pass this suite.
# ---------------------------------------------------------------------------
mkdir -p "$claude_dir/.claude-plugin"
printf '{"name":"claudio-dr","version":"0.0.1-legacy"}\n' > "$claude_dir/.claude-plugin/plugin.json"

legacy_output="$(run_install "$tmp" --global)"
echo "$legacy_output" | grep -qF "$claude_dir/.claude-plugin/plugin.json" \
  || { echo "FAIL: --global did not name the legacy direct copy; output: $legacy_output" >&2; exit 1; }
echo "$legacy_output" | grep -q "will not remove" \
  || { echo "FAIL: --global did not state that it leaves the legacy copy in place" >&2; exit 1; }
[[ "$(jq -r '.version' "$claude_dir/.claude-plugin/plugin.json")" == "0.0.1-legacy" ]] \
  || { echo "FAIL: --global deleted or overwrote the legacy direct copy" >&2; exit 1; }

# --status reports it too, so an operator can find it without re-running an install.
legacy_status="$(run_install "$tmp" --status)"
echo "$legacy_status" | grep -q "will not remove" \
  || { echo "FAIL: --status did not report the legacy direct copy" >&2; exit 1; }

rm -rf "$claude_dir/.claude-plugin"

# ---------------------------------------------------------------------------
# --status: the legacy report names only catalog-owned entries
#
# The report must never hand the operator a directory such as ~/.claude/agents
# as a removal target: the user's own agents and Claude Code's own
# skills/synced/ store live under the same names. Only an entry whose name
# comes from plugins/claudio-dr/ is legacy.
# ---------------------------------------------------------------------------
mkdir -p "$claude_dir/agents"
printf 'not from this catalog\n' > "$claude_dir/agents/personal-not-catalog.md"

ownership_status="$(run_install "$tmp" --status)"
if echo "$ownership_status" | grep -qF "personal-not-catalog.md"; then
  echo "FAIL: --status named a user-owned agent as a legacy path" >&2; exit 1
fi
if echo "$ownership_status" | grep -qE "^ +${claude_dir}/agents\$"; then
  echo "FAIL: --status named the whole agents directory as a legacy path" >&2; exit 1
fi
if echo "$ownership_status" | grep -q "will not remove"; then
  echo "FAIL: --status reported a legacy copy with only user-owned entries present" >&2; exit 1
fi

# The positive half: an entry carrying a catalog-owned name is still reported,
# so the negative assertions above cannot pass by reporting nothing at all.
catalog_agent="$(basename "$(find "$repository_root/plugins/claudio-dr/agents" -maxdepth 1 -type f -name '*.md' | head -1)")"
[[ -n "$catalog_agent" ]] || { echo "FAIL: no catalog agent found to build the positive case" >&2; exit 1; }
cp "$repository_root/plugins/claudio-dr/agents/$catalog_agent" "$claude_dir/agents/$catalog_agent"

ownership_status="$(run_install "$tmp" --status)"
echo "$ownership_status" | grep -qF "$claude_dir/agents/$catalog_agent" \
  || { echo "FAIL: --status did not name the catalog-owned legacy agent; output: $ownership_status" >&2; exit 1; }
if echo "$ownership_status" | grep -qF "personal-not-catalog.md"; then
  echo "FAIL: --status named a user-owned agent alongside the catalog-owned one" >&2; exit 1
fi

rm -rf "$claude_dir/agents"

# ---------------------------------------------------------------------------
# --status: an outdated registered version is reported as that version
#
# Synthesizing the cache path from the catalog version makes a stale registered
# copy indistinguishable from no installation, which is the exact drift this
# migration exists to surface.
# ---------------------------------------------------------------------------
registered_cache="$claude_dir/plugins/cache/dr-agents/claudio-dr"
plugin_state="$claude_dir/plugins/installed_plugins.json"
[[ -f "$plugin_state" ]] \
  || { echo "FAIL: --global left no Claude plugin state at $plugin_state" >&2; exit 1; }
state_backup="$tmp/installed-plugins-backup.json"
cp "$plugin_state" "$state_backup"
stale_backup="$tmp/registered-cache-backup"
mv "$registered_cache" "$stale_backup"

# Record an installation in Claude's plugin state exactly as the CLI does.
register_claudio() {
  local version="$1"
  mkdir -p "$registered_cache/$version/.claude-plugin"
  printf '{"name":"claudio-dr","version":"%s"}\n' "$version" \
    > "$registered_cache/$version/.claude-plugin/plugin.json"
  jq -n --arg path "$registered_cache/$version" --arg version "$version" \
    '{version: 2, plugins: {"claudio-dr@dr-agents": [{scope: "user", installPath: $path, version: $version}]}}' \
    > "$plugin_state"
}

register_claudio 0.0.1-stale

stale_status="$(run_install "$tmp" --status)"
echo "$stale_status" | grep -qF "0.0.1-stale" \
  || { echo "FAIL: --status did not report the stale registered version; output: $stale_status" >&2; exit 1; }
if echo "$stale_status" | grep -qE "^ +claudio-dr +not installed +\\(${registered_cache}"; then
  echo "FAIL: --status reported a stale registered install as not installed" >&2; exit 1
fi
if echo "$stale_status" | grep -qF "${registered_cache}/${claudio_ver}/"; then
  echo "FAIL: --status synthesized the cache path from the catalog version" >&2; exit 1
fi

# ---------------------------------------------------------------------------
# --status: the registered installation wins over an unregistered leftover
#
# Several cache directories can coexist. Reading whichever one the glob lists
# last is not the registration, and the listing is not even version order:
# 0.1.10 sorts lexically before 0.1.9, so a glob scan reports the older one.
# The registered path in plugins/installed_plugins.json is the only record.
# ---------------------------------------------------------------------------
rm -rf "$registered_cache"
mkdir -p "$registered_cache/0.1.9/.claude-plugin"
printf '{"name":"claudio-dr","version":"0.1.9"}\n' \
  > "$registered_cache/0.1.9/.claude-plugin/plugin.json"
register_claudio 0.1.10

multi_status="$(run_install "$tmp" --status)"
echo "$multi_status" | grep -qF "claudio-dr  0.1.10  (${registered_cache}/0.1.10/)" \
  || { echo "FAIL: --status did not report the registered cache 0.1.10; output: $multi_status" >&2; exit 1; }
if echo "$multi_status" | grep -qF "${registered_cache}/0.1.9/"; then
  echo "FAIL: --status reported an unregistered leftover cache over the registered one" >&2; exit 1
fi

# The other direction: with the same two caches present, registering the lower
# version must report the lower one. Asserting only the higher version would
# pass against any "newest cache wins" rule, which is still not the
# registration.
register_claudio 0.1.9
lower_status="$(run_install "$tmp" --status)"
echo "$lower_status" | grep -qF "claudio-dr  0.1.9  (${registered_cache}/0.1.9/)" \
  || { echo "FAIL: --status did not report the registered cache 0.1.9; output: $lower_status" >&2; exit 1; }
if echo "$lower_status" | grep -qF "${registered_cache}/0.1.10/"; then
  echo "FAIL: --status preferred a higher unregistered cache over the registered one" >&2; exit 1
fi

rm -rf "$registered_cache"
mv "$stale_backup" "$registered_cache"
mv "$state_backup" "$plugin_state"

# ---------------------------------------------------------------------------
# --global: the claude CLI is a hard dependency of the marketplace route
#
# The canonical route runs through `claude plugin`; with no such binary the
# installer must fail loudly rather than fall back to a second mechanism.
# ---------------------------------------------------------------------------
# Build a PATH that keeps every ordinary tool the installer needs but resolves
# no `claude` at all: dropping PATH entirely would only hide `bash`.
no_claude_bin="$tmp/no-claude-bin"
mkdir -p "$no_claude_bin"
cp "$fake_bin/codex" "$no_claude_bin/codex"
no_claude_path="$no_claude_bin"
while IFS= read -r dir; do
  [[ -z "$dir" ]] && continue
  [[ -x "$dir/claude" ]] && continue
  no_claude_path="$no_claude_path:$dir"
done < <(tr ':' '\n' <<< "$PATH")
[[ -z "$(PATH="$no_claude_path" command -v claude || true)" ]] \
  || { echo "FAIL: the no-claude PATH still resolves a claude binary" >&2; exit 1; }

if out="$( cd "$tmp" && HOME="$fake_home" CODEX_CONFIG_DIR="$codex_dir" CLAUDE_CONFIG_DIR="$claude_dir" \
    CODEX_CALL_LOG="$codex_call_log" CLAUDE_CALL_LOG="$claude_call_log" \
    PATH="$no_claude_path" bash "$repository_root/bin/install" --global 2>&1 )"; then
  echo "FAIL: --global should fail when the claude CLI is absent; output: $out" >&2
  exit 1
fi
echo "$out" | grep -q "claude CLI is required" \
  || { echo "FAIL: --global failed without naming the missing claude CLI; output: $out" >&2; exit 1; }

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
status_output="$(run_install "$fake_repo" --status)"
echo "$status_output" | grep -q "claudio-dr" || { echo "FAIL: status output missing claudio-dr" >&2; exit 1; }
echo "$status_output" | grep -q "cody-dr"    || { echo "FAIL: status output missing cody-dr" >&2; exit 1; }
echo "$status_output" | grep -q "agents"     || { echo "FAIL: status output missing agents" >&2; exit 1; }

# ---------------------------------------------------------------------------
# --status: report the registered Cody version, not a catalog/cache guess
#
# Both directions matter. The first rejects "last lexical cache wins" while
# the second rejects "newest cache wins"; together they prove the status line
# follows Codex's registration state.
# ---------------------------------------------------------------------------
for cached_version in 0.1.9 0.1.10; do
  cached_manifest="$codex_dir/plugins/cache/dr-agents/cody-dr/$cached_version/.codex-plugin/plugin.json"
  mkdir -p "$(dirname "$cached_manifest")"
  printf '{"name":"cody-dr","version":"%s"}\n' "$cached_version" > "$cached_manifest"
done

registration_failures=0
for registered_version in 0.1.10 0.1.9; do
  printf '%s\n' "$registered_version" > "$codex_dir/fake-registered-cody-version"
  registered_status="$(run_install "$fake_repo" --status)"
  expected_line="  cody-dr     $registered_version  ($codex_dir/plugins/cache/dr-agents/cody-dr/$registered_version/)"
  if ! grep -qF "$expected_line" <<< "$registered_status"; then
    echo "FAIL: --status did not report registered Cody $registered_version; expected: $expected_line" >&2
    registration_failures=$((registration_failures + 1))
  fi
done
[[ "$registration_failures" -eq 0 ]] || exit 1

# Restore the catalog registration for subsequent cases.
printf '%s\n' "$cody_ver" > "$codex_dir/fake-registered-cody-version"

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
# --repo: conflict detected when an existing file differs
#
# Conflict safety used to be asserted through --global, which copied a plugin
# tree into ~/.claude/. dr-agents#427 removed that copy, so --repo is now the
# only mode that runs install_plugin_dir. The coverage moves with it rather
# than disappearing.
# ---------------------------------------------------------------------------
readonly conflict_repo="$tmp/conflict-repo"
mkdir -p "$conflict_repo"
run_install "$conflict_repo" --repo >/dev/null
echo "tampered" > "$conflict_repo/.claude/.claude-plugin/plugin.json"
if run_install "$conflict_repo" --repo >/dev/null 2>&1; then
  echo "FAIL: expected conflict exit on tampered file, got success" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# --repo --force: identical files are skipped silently (no WARNING, no error)
# ---------------------------------------------------------------------------
rm -rf "$conflict_repo/.claude"
run_install "$conflict_repo" --repo >/dev/null 2>&1

force_clean_output="$(run_install "$conflict_repo" --repo --force 2>&1)"
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
