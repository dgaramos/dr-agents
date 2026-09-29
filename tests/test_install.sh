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
# dr-agents#455: --global re-records the version on an already-installed plugin
#
# `claude plugin install` no-ops on an already-installed plugin and leaves the
# recorded version alone, so `agents update --global` used to print "Global
# install complete" while `claude plugin list` still reported the version from
# whenever the plugin was first installed. The catalog's job is to leave every
# reading of the installed version agreeing.
#
# The fake models that no-op (tests/helpers/fake-claude.sh); without it this
# test would pass against a CLI stub that was never wrong.
# ---------------------------------------------------------------------------
recorded_claudio_version() {
  jq -r '(.plugins["claudio-dr@dr-agents"] // []) | map(.version // empty) | first // empty' \
    "$claude_dir/plugins/installed_plugins.json"
}

stale_version="0.0.1-stale"
stale_path="$claude_dir/plugins/cache/dr-agents/claudio-dr/$stale_version"
mkdir -p "$stale_path/.claude-plugin"
printf '{"name":"claudio-dr","version":"%s"}\n' "$stale_version" \
  > "$stale_path/.claude-plugin/plugin.json"
jq -n --arg path "$stale_path" --arg version "$stale_version" \
  '{version: 2, plugins: {"claudio-dr@dr-agents": [{scope: "user", installPath: $path, version: $version}]}}' \
  > "$claude_dir/plugins/installed_plugins.json"

[[ "$(recorded_claudio_version)" == "$stale_version" ]] \
  || { echo "FAIL: could not stage a stale recorded version" >&2; exit 1; }

stale_output="$(run_install "$tmp" --global)"

grep -qF "plugin update claudio-dr@dr-agents" "$claude_call_log" \
  || { echo "FAIL: --global did not dispatch 'plugin update' to re-record the version" >&2; exit 1; }
[[ "$(recorded_claudio_version)" == "$claudio_ver" ]] \
  || { echo "FAIL: --global left the recorded version at $(recorded_claudio_version), not $claudio_ver" >&2; exit 1; }
echo "$stale_output" | grep -q "Global install complete" \
  || { echo "FAIL: --global did not complete after re-recording; output: $stale_output" >&2; exit 1; }
rm -rf "$stale_path"

# ---------------------------------------------------------------------------
# dr-agents#455: --global does not claim completion when the version disagrees
#
# The failure path. If the dispatch does not leave the recorded version
# matching the catalog, the flow must say so rather than print "Global install
# complete" over the top of a disagreement it can see.
#
# A dedicated stub stands in for a CLI whose `update` does not honour the
# re-record — the realistic failure, and the one the gate exists to catch.
# Pointing this at the shared fake would mean asserting a defect into the fake
# that the other cases depend on not having.
# ---------------------------------------------------------------------------
lying_home="$tmp/lying-home"
lying_claude_dir="$lying_home/.claude"
lying_bin="$tmp/lying-bin"
mkdir -p "$lying_home" "$lying_bin"
cp "$repository_root/tests/helpers/fake-codex.sh" "$lying_bin/codex"
# Neuter only the update path's re-record; everything else behaves as the fake.
sed 's/^  updated="\$(record_install)"$/  updated="$existing"/' \
  "$repository_root/tests/helpers/fake-claude.sh" > "$lying_bin/claude"
grep -qF 'updated="$existing"' "$lying_bin/claude" \
  || { echo "FAIL: could not build the non-re-recording claude stub" >&2; exit 1; }
chmod +x "$lying_bin/codex" "$lying_bin/claude"

# Install once so the plugin is present, then stage a stale recording for the
# stub to fail to repair.
( cd "$tmp" \
  && HOME="$lying_home" CODEX_CONFIG_DIR="$lying_home/.codex" \
     CLAUDE_CONFIG_DIR="$lying_claude_dir" \
     CODEX_CALL_LOG="$tmp/lying-codex.log" CLAUDE_CALL_LOG="$tmp/lying-claude.log" \
     PATH="$fake_bin:$PATH" \
     bash "$repository_root/bin/install" --global >/dev/null 2>&1 )

lying_stale="$lying_claude_dir/plugins/cache/dr-agents/claudio-dr/$stale_version"
mkdir -p "$lying_stale/.claude-plugin"
printf '{"name":"claudio-dr","version":"%s"}\n' "$stale_version" \
  > "$lying_stale/.claude-plugin/plugin.json"
jq -n --arg path "$lying_stale" --arg version "$stale_version" \
  '{version: 2, plugins: {"claudio-dr@dr-agents": [{scope: "user", installPath: $path, version: $version}]}}' \
  > "$lying_claude_dir/plugins/installed_plugins.json"

if lying_output="$( cd "$tmp" \
    && HOME="$lying_home" CODEX_CONFIG_DIR="$lying_home/.codex" \
       CLAUDE_CONFIG_DIR="$lying_claude_dir" \
       CODEX_CALL_LOG="$tmp/lying-codex.log" CLAUDE_CALL_LOG="$tmp/lying-claude.log" \
       PATH="$lying_bin:$PATH" \
       bash "$repository_root/bin/install" --global 2>&1 )"; then
  echo "FAIL: --global exited 0 with a recorded version that disagrees with the catalog" >&2
  echo "$lying_output" >&2
  exit 1
fi
echo "$lying_output" | grep -qF "$stale_version" \
  || { echo "FAIL: --global did not name the disagreeing recorded version; output: $lying_output" >&2; exit 1; }
echo "$lying_output" | grep -qF "$claudio_ver" \
  || { echo "FAIL: --global did not name the catalog version it expected; output: $lying_output" >&2; exit 1; }
if echo "$lying_output" | grep -q "Global install complete"; then
  echo "FAIL: --global claimed completion despite a version disagreement" >&2; exit 1
fi

# ---------------------------------------------------------------------------
# dr-agents#455: the gate reads the RECORDED version, not the payload manifest
#
# The two readings are distinct, and every other fixture here moves them
# together — so they cannot tell apart a gate that reads the recorded
# `version` field from one that reads the manifest at the recorded
# installPath. This one decouples them deliberately: the recorded field is
# stale while the manifest at that same installPath already reports the
# catalog version.
#
# That is the state issue #455 is actually about — `claude plugin list` prints
# the field, not the manifest. A gate reading the manifest sees the catalog
# version here and prints "Global install complete" over a recording that is
# still wrong.
# ---------------------------------------------------------------------------
decoupled_path="$lying_claude_dir/plugins/cache/dr-agents/claudio-dr/$stale_version"
mkdir -p "$decoupled_path/.claude-plugin"
# The manifest at the recorded path is CURRENT ...
printf '{"name":"claudio-dr","version":"%s"}\n' "$claudio_ver" \
  > "$decoupled_path/.claude-plugin/plugin.json"
# ... while the field Claude actually records, and prints, is stale.
jq -n --arg path "$decoupled_path" --arg version "$stale_version" \
  '{version: 2, plugins: {"claudio-dr@dr-agents": [{scope: "user", installPath: $path, version: $version}]}}' \
  > "$lying_claude_dir/plugins/installed_plugins.json"

# Guard the fixture itself: if these two ever agree, the test proves nothing.
[[ "$(jq -r '.version' "$decoupled_path/.claude-plugin/plugin.json")" == "$claudio_ver" \
   && "$(jq -r '(.plugins["claudio-dr@dr-agents"] // []) | map(.version // empty) | first // empty' \
         "$lying_claude_dir/plugins/installed_plugins.json")" == "$stale_version" ]] \
  || { echo "FAIL: could not stage a decoupled recorded-version/manifest state" >&2; exit 1; }

if decoupled_output="$( cd "$tmp" \
    && HOME="$lying_home" CODEX_CONFIG_DIR="$lying_home/.codex" \
       CLAUDE_CONFIG_DIR="$lying_claude_dir" \
       CODEX_CALL_LOG="$tmp/lying-codex.log" CLAUDE_CALL_LOG="$tmp/lying-claude.log" \
       PATH="$lying_bin:$PATH" \
       bash "$repository_root/bin/install" --global 2>&1 )"; then
  echo "FAIL: --global exited 0 while Claude still recorded $stale_version" >&2
  echo "      (the gate read the manifest at installPath, not the recorded version)" >&2
  echo "$decoupled_output" >&2
  exit 1
fi
echo "$decoupled_output" | grep -qF "$stale_version" \
  || { echo "FAIL: --global did not name the stale recorded version; output: $decoupled_output" >&2; exit 1; }
if echo "$decoupled_output" | grep -q "Global install complete"; then
  echo "FAIL: --global claimed completion over a stale recorded version" >&2; exit 1
fi


# ---------------------------------------------------------------------------
# dr-agents#455: a first-time --global still installs and records correctly
#
# The edge case that rules out replacing `install` with `update`. The real
# `claude plugin update` exits non-zero on a plugin that is not installed, so
# the two dispatches are a pair, not a redundancy.
# ---------------------------------------------------------------------------
fresh_home="$tmp/fresh-home"
fresh_claude_dir="$fresh_home/.claude"
mkdir -p "$fresh_home"
fresh_output="$( cd "$tmp" \
  && HOME="$fresh_home" CODEX_CONFIG_DIR="$fresh_home/.codex" \
     CLAUDE_CONFIG_DIR="$fresh_claude_dir" \
     CODEX_CALL_LOG="$tmp/fresh-codex.log" CLAUDE_CALL_LOG="$tmp/fresh-claude.log" \
     PATH="$fake_bin:$PATH" \
     bash "$repository_root/bin/install" --global 2>&1 )"
echo "$fresh_output" | grep -q "Global install complete" \
  || { echo "FAIL: first-time --global did not complete; output: $fresh_output" >&2; exit 1; }
fresh_recorded="$(jq -r '(.plugins["claudio-dr@dr-agents"] // []) | map(.version // empty) | first // empty' \
  "$fresh_claude_dir/plugins/installed_plugins.json")"
[[ "$fresh_recorded" == "$claudio_ver" ]] \
  || { echo "FAIL: first-time --global recorded $fresh_recorded, not $claudio_ver" >&2; exit 1; }

# ---------------------------------------------------------------------------
# --global --force: refreshes both marketplace snapshots before installing
#
# Neither plugin CLI has a --force flag, so --force cannot be forwarded
# verbatim. On this route it means "do not install from a cached snapshot":
# without the refresh, `agents update --global --force` would re-register the
# catalog as it stood before the pull it just performed. The codex refresh
# only applies to Git marketplaces and fails for a local-path catalog; that
# failure is a no-op, so the install must still complete.
# ---------------------------------------------------------------------------
: > "$claude_call_log"
: > "$codex_call_log"
force_global_output="$(run_install "$tmp" --global --force)"

grep -qF "plugin marketplace update dr-agents" "$claude_call_log" \
  || { echo "FAIL: --global --force did not refresh the Claude marketplace snapshot" >&2; exit 1; }
grep -qF "plugin marketplace upgrade dr-agents" "$codex_call_log" \
  || { echo "FAIL: --global --force did not refresh the Codex marketplace snapshot" >&2; exit 1; }
grep -qF "plugin install claudio-dr@dr-agents" "$claude_call_log" \
  || { echo "FAIL: --global --force did not install claudio-dr after the refresh" >&2; exit 1; }
grep -qF "plugin add cody-dr@dr-agents" "$codex_call_log" \
  || { echo "FAIL: --global --force did not install cody-dr after the refresh" >&2; exit 1; }
echo "$force_global_output" | grep -q "nothing to refresh" \
  || { echo "FAIL: --global --force did not report the Codex refresh as a no-op" >&2; exit 1; }
echo "$force_global_output" | grep -q "Global install complete" \
  || { echo "FAIL: --global --force did not complete; output: $force_global_output" >&2; exit 1; }

# Without --force neither snapshot is refreshed: an ordinary re-install must
# not pay for a catalog fetch it did not ask for.
: > "$claude_call_log"
: > "$codex_call_log"
run_install "$tmp" --global >/dev/null
if grep -qF "marketplace update" "$claude_call_log" || grep -qF "marketplace upgrade" "$codex_call_log"; then
  echo "FAIL: --global without --force refreshed a marketplace snapshot" >&2; exit 1
fi

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

# ---------------------------------------------------------------------------
# dr-agents#461: the jq and awk readings of installed_plugins.json must agree
#
# The gate's selection rule — "the user-scoped claudio-dr@dr-agents entry, or
# the first entry when there is none" — is implemented twice, once in jq and
# once in awk. Only the jq branch runs on a developer machine, so a fallback
# that selects differently is wrong in silence: that is exactly how the
# user-scope selection ended up missing from the awk branch.
#
# So this does not check the two branches separately against expected values.
# It runs every fixture through BOTH and asserts they answer the same thing,
# then checks that one shared answer. A fixture added here is automatically
# covered on both branches, and a future field added to
# registered_claudio_field() inherits the same comparison.
# ---------------------------------------------------------------------------
readers="$tmp/readers.sh"
# Selection and projection are separate functions on purpose (see bin/install),
# so all three are extracted. Naming them explicitly is also the check that the
# split still exists: collapsing them back into one function, which is what
# made the wrong composition order representable, fails here.
awk '
  /^registered_claudio_entry\(\) \{$/ { inside = 1 }
  /^registered_claudio_entry_field\(\) \{$/ { inside = 1 }
  /^registered_claudio_field\(\) \{$/ { inside = 1 }
  inside { print }
  inside && /^\}$/ { inside = 0 }
' "$repository_root/bin/install" > "$readers"
for reader_fn in registered_claudio_entry registered_claudio_entry_field registered_claudio_field; do
  grep -q "^$reader_fn() {\$" "$readers" \
    || { echo "FAIL: could not extract $reader_fn from bin/install" >&2; exit 1; }
done
grep -q '^}$' "$readers" \
  || { echo "FAIL: extracted readers are not closed" >&2; exit 1; }
bash -n "$readers" \
  || { echo "FAIL: extracted readers do not parse" >&2; exit 1; }
# registered_claudio_entry() must not be able to select BY a field: a field
# name reaching it is how projection and selection get composed in the wrong
# order. This is a structural assertion, not a behavioural one.
entry_body="$tmp/entry-body.sh"
awk '
  /^registered_claudio_entry\(\) \{$/ { inside = 1 }
  inside { print }
  inside && /^\}$/ { exit }
' "$repository_root/bin/install" > "$entry_body"
if grep -Eq 'local[[:space:]]+field=|\$\{?2\}?' "$entry_body"; then
  echo "FAIL: registered_claudio_entry() reads a second argument; selection must not see a field" >&2
  exit 1
fi

# A PATH with the tools the awk branch needs and deliberately without jq.
nojq_bin="$tmp/nojq-bin"
mkdir -p "$nojq_bin"
# bash itself must be on it too: the reader runs under this PATH, and a PATH
# that cannot resolve the shell fails for the wrong reason.
for tool in bash awk sed grep cat basename sort tail head printf dirname cmp; do
  tool_path="$(command -v "$tool" 2>/dev/null)" || continue
  ln -sf "$tool_path" "$nojq_bin/$tool"
done
if PATH="$nojq_bin" command -v jq >/dev/null 2>&1; then
  echo "FAIL: the no-jq PATH still resolves jq" >&2
  exit 1
fi

read_field() {
  # $1: PATH to run under, $2: state file, $3: field
  PATH="$1" bash -c '
    source "$1"
    registered_claudio_field "$2" "$3"
  ' _ "$readers" "$2" "$3"
}

fixtures="$tmp/reader-fixtures"
mkdir -p "$fixtures"

# Fixture: a project-scoped entry recorded BEFORE the user-scoped one. This is
# the shape the no-jq probe on PR #461 failed on — the awk branch returned the
# project entry while jq returned the user entry.
jq -n '{
  version: 2,
  plugins: {
    "some-other@dr-agents": [
      {scope: "user", version: "9.9.9-other", installPath: "/other/path"}
    ],
    "claudio-dr@dr-agents": [
      {scope: "project", version: "0.0.1-project", installPath: "/project/claudio-dr"},
      {scope: "user", version: "0.1.43-user", installPath: "/user/claudio-dr"}
    ],
    "zz-later@dr-agents": [
      {scope: "user", version: "7.7.7-later", installPath: "/later/path"}
    ]
  }
}' > "$fixtures/mixed-scope.json"

# The same state as Claude Code actually writes it: one line, no whitespace.
jq -c . "$fixtures/mixed-scope.json" > "$fixtures/mixed-scope-compact.json"

# Only a project entry: there is no user entry to prefer, so the rule falls
# through to the first one. Without the array terminator the awk branch would
# read the NEXT plugin key's field here.
jq -n '{
  version: 2,
  plugins: {
    "claudio-dr@dr-agents": [
      {scope: "project", version: "0.0.1-project", installPath: "/project/claudio-dr"}
    ],
    "zz-later@dr-agents": [
      {scope: "user", version: "7.7.7-later", installPath: "/later/path"}
    ]
  }
}' > "$fixtures/project-only.json"

# Nothing recorded for claudio-dr at all: both branches must print nothing
# rather than borrowing another plugin's entry.
jq -n '{
  version: 2,
  plugins: {
    "zz-later@dr-agents": [
      {scope: "user", version: "7.7.7-later", installPath: "/later/path"}
    ]
  }
}' > "$fixtures/absent.json"

# Round 4 of dr-agents#461: the selected user entry has NO version, while a
# project entry does. The jq branch mapped the field over every entry before
# taking the first non-empty result, so it answered 0.1.43-project here — the
# gate would have approved `Global install complete` by borrowing another
# scope's version. The awk branch, which selects the entry first, returned
# nothing. The rule says nothing: there is no version recorded on the user
# installation.
jq -n '{
  version: 2,
  plugins: {
    "claudio-dr@dr-agents": [
      {scope: "project", version: "0.1.43-project", installPath: "/project/claudio-dr"},
      {scope: "user", installPath: "/user/claudio-dr"}
    ],
    "zz-later@dr-agents": [
      {scope: "user", version: "7.7.7-later", installPath: "/later/path"}
    ]
  }
}' > "$fixtures/user-entry-without-version.json"

# fixture | field | expected shared answer
reader_cases=(
  "user-entry-without-version.json|version|"
  "user-entry-without-version.json|installPath|/user/claudio-dr"
  "mixed-scope.json|version|0.1.43-user"
  "mixed-scope.json|installPath|/user/claudio-dr"
  "mixed-scope-compact.json|version|0.1.43-user"
  "mixed-scope-compact.json|installPath|/user/claudio-dr"
  "project-only.json|version|0.0.1-project"
  "project-only.json|installPath|/project/claudio-dr"
  "absent.json|version|"
  "absent.json|installPath|"
)

for reader_case in "${reader_cases[@]}"; do
  IFS='|' read -r case_fixture case_field case_expected <<< "$reader_case"
  case_state="$fixtures/$case_fixture"

  with_jq="$(read_field "$PATH" "$case_state" "$case_field")"
  without_jq="$(read_field "$nojq_bin" "$case_state" "$case_field")"

  # The differential assertion. This is the one that would have caught #461.
  [[ "$with_jq" == "$without_jq" ]] || {
    echo "FAIL: jq and awk disagree on $case_fixture field $case_field:" >&2
    echo "      jq   -> '$with_jq'" >&2
    echo "      awk  -> '$without_jq'" >&2
    exit 1
  }
  [[ "$with_jq" == "$case_expected" ]] || {
    echo "FAIL: $case_fixture field $case_field read '$with_jq', expected '$case_expected'" >&2
    exit 1
  }
done

# ---------------------------------------------------------------------------
# dr-agents#461 round 4: the shape space, generated — not a fixture table
#
# The cases above are named regressions, one per round of this finding. They
# share a limit the round-3 reply disclosed and round 4 then hit within the
# hour: "the differential only covers fixtures in the table. A JSON shape no
# fixture exhibits can still diverge." A hand-written table cannot cover
# shapes nobody thought of, and a pure differential cannot catch the two
# parsers being wrong in the same way.
#
# So this block does not hand-write shapes and does not only compare the two
# parsers. It enumerates the space the selection rule is defined over —
# entry count x scope x whether the requested field is present and of what
# type — and checks both parsers against an ORACLE computed from the same
# parameters the fixture was built from. Shared wrongness fails here; the
# differential alone would pass it.
# ---------------------------------------------------------------------------

# scope code: u=user, p=project, n=no scope key
# value code: s=string, m=missing, i=non-string (a number)
sweep_kinds=(us um ui ps pm pi ns nm ni)

# Build one entry object. $1 kind, $2 tag, $3 field name.
sweep_entry() {
  local kind="$1" tag="$2" field="$3"
  local scope_code="${kind:0:1}" value_code="${kind:1:1}"
  local parts="\"id\": \"$tag\""
  case "$scope_code" in
    u) parts="$parts, \"scope\": \"user\"" ;;
    p) parts="$parts, \"scope\": \"project\"" ;;
  esac
  case "$value_code" in
    s) parts="$parts, \"$field\": \"$tag-value\"" ;;
    i) parts="$parts, \"$field\": 7" ;;
  esac
  printf '{%s}' "$parts"
}

# The rule, stated independently of both parsers: prefer the first
# user-scoped entry, else the first entry, then read the field off THAT entry
# and return it only when it is a string.
sweep_oracle() {
  local field="$1"; shift
  local kinds=("$@")
  local chosen_index=-1 index=0 kind
  for kind in ${kinds+"${kinds[@]}"}; do
    if [[ "${kind:0:1}" == "u" ]]; then chosen_index=$index; break; fi
    index=$((index + 1))
  done
  if [[ $chosen_index -eq -1 && ${#kinds[@]} -gt 0 ]]; then chosen_index=0; fi
  if [[ $chosen_index -eq -1 ]]; then printf ''; return 0; fi
  local chosen="${kinds[$chosen_index]}"
  if [[ "${chosen:1:1}" == "s" ]]; then printf 'e%s-value' "$chosen_index"; fi
}

sweep_checked=0
sweep_case() {
  local field="$1"; shift
  local kinds=(${1+"$@"})
  local entries="" index=0 kind
  for kind in ${kinds+"${kinds[@]}"}; do
    [[ -n "$entries" ]] && entries="$entries, "
    entries="$entries$(sweep_entry "$kind" "e$index" "$field")"
    index=$((index + 1))
  done

  local state="$fixtures/sweep.json"
  # A later plugin key is always present: reading past the array terminator
  # must not reach it.
  printf '{"version": 2, "plugins": {"claudio-dr@dr-agents": [%s], "zz-later@dr-agents": [{"scope": "user", "version": "7.7.7-later", "installPath": "/later/path"}]}}\n' \
    "$entries" > "$state"
  jq -e . "$state" >/dev/null \
    || { echo "FAIL: generated sweep fixture is not valid JSON: $entries" >&2; exit 1; }

  local expected
  expected="$(sweep_oracle "$field" ${kinds+"${kinds[@]}"})"

  local got_jq got_awk
  got_jq="$(read_field "$PATH" "$state" "$field")"
  got_awk="$(read_field "$nojq_bin" "$state" "$field")"

  [[ "$got_jq" == "$got_awk" ]] || {
    echo "FAIL: jq and awk disagree on generated shape [${kinds[*]-}] field $field:" >&2
    echo "      jq   -> '$got_jq'" >&2
    echo "      awk  -> '$got_awk'" >&2
    exit 1
  }
  # The oracle is what makes this more than a differential: it fails even when
  # both parsers agree on the wrong answer.
  [[ "$got_jq" == "$expected" ]] || {
    echo "FAIL: generated shape [${kinds[*]-}] field $field read '$got_jq', rule says '$expected'" >&2
    echo "      state: $(cat "$state")" >&2
    exit 1
  }
  sweep_checked=$((sweep_checked + 1))
}

for sweep_field in version installPath; do
  sweep_case "$sweep_field"
  for sweep_a in "${sweep_kinds[@]}"; do
    sweep_case "$sweep_field" "$sweep_a"
    for sweep_b in "${sweep_kinds[@]}"; do
      sweep_case "$sweep_field" "$sweep_a" "$sweep_b"
    done
  done
done

# The sweep is only as good as its size; an empty or collapsed loop would pass
# silently. 2 fields x (1 empty + 9 single + 81 pairs).
[[ "$sweep_checked" -eq 182 ]] \
  || { echo "FAIL: reader shape sweep checked $sweep_checked cases, expected 182" >&2; exit 1; }

# Guard the guard: the differential is worthless if the no-jq run silently
# used jq anyway. Prove the awk branch is the one that answered.
PATH="$nojq_bin" bash -c '
  source "$1"
  command -v jq >/dev/null 2>&1 && exit 1
  exit 0
' _ "$readers" \
  || { echo "FAIL: the no-jq reader run could still see jq" >&2; exit 1; }

# ---------------------------------------------------------------------------
# dr-agents#461: a healthy global install is not rejected because a
# project-scoped entry happens to be recorded first.
# ---------------------------------------------------------------------------
mixed_home="$tmp/mixed-home"
mixed_claude_dir="$mixed_home/.claude"
mkdir -p "$mixed_home"
( cd "$tmp" \
  && HOME="$mixed_home" CODEX_CONFIG_DIR="$mixed_home/.codex" \
     CLAUDE_CONFIG_DIR="$mixed_claude_dir" \
     CODEX_CALL_LOG="$tmp/mixed-codex.log" CLAUDE_CALL_LOG="$tmp/mixed-claude.log" \
     PATH="$fake_bin:$PATH" \
     bash "$repository_root/bin/install" --global >/dev/null 2>&1 )

mixed_state="$mixed_claude_dir/plugins/installed_plugins.json"
# Prepend a stale project-scoped registration to the healthy user-scoped one.
jq '.plugins["claudio-dr@dr-agents"] =
      ([{scope: "project", version: "0.0.1-project", installPath: "/project/claudio-dr"}]
       + .plugins["claudio-dr@dr-agents"])' \
  "$mixed_state" > "$mixed_state.tmp" && mv "$mixed_state.tmp" "$mixed_state"

# Guard the fixture: the project entry must really come first, and the user
# entry must really be current, or this proves nothing.
[[ "$(jq -r '.plugins["claudio-dr@dr-agents"][0].scope' "$mixed_state")" == "project" \
   && "$(jq -r 'first(.plugins["claudio-dr@dr-agents"][] | select(.scope == "user") | .version)' \
         "$mixed_state")" == "$claudio_ver" ]] \
  || { echo "FAIL: could not stage a mixed-scope recorded state" >&2; exit 1; }

mixed_output="$( cd "$tmp" \
  && HOME="$mixed_home" CODEX_CONFIG_DIR="$mixed_home/.codex" \
     CLAUDE_CONFIG_DIR="$mixed_claude_dir" \
     CODEX_CALL_LOG="$tmp/mixed-codex.log" CLAUDE_CALL_LOG="$tmp/mixed-claude.log" \
     PATH="$fake_bin:$PATH" \
     bash "$repository_root/bin/install" --global 2>&1 )" || {
  echo "FAIL: --global rejected a healthy install over a project-scoped entry" >&2
  echo "$mixed_output" >&2
  exit 1
}
echo "$mixed_output" | grep -q "Global install complete" \
  || { echo "FAIL: mixed-scope --global did not complete; output: $mixed_output" >&2; exit 1; }
# The project entry must survive the run: if the fake flattened it away, the
# gate was never asked the mixed-scope question.
[[ "$(jq -r '[.plugins["claudio-dr@dr-agents"][] | select(.scope == "project")] | length' \
      "$mixed_state")" == "1" ]] \
  || { echo "FAIL: the project-scoped entry did not survive --global" >&2; exit 1; }

# ---------------------------------------------------------------------------
# dr-agents#461 round 4, end to end on the reachable path.
#
# The round-4 shape cannot survive --global: the `update` dispatch re-records
# the user entry with a version before the gate reads it, so a user entry
# missing `version` is not reachable through that flow (stated in the reply
# rather than faked here). --status is different — it dispatches nothing and
# reads the recorded state as it stands, so a user entry missing `installPath`
# reaches the reader untouched. With the projection-before-selection defect,
# registered_claudio_cache() answered with the PROJECT entry's path and
# --status reported another scope's directory as the global installation.
# ---------------------------------------------------------------------------
borrow_home="$tmp/borrow-home"
borrow_claude_dir="$borrow_home/.claude"
mkdir -p "$borrow_home"
( cd "$tmp" \
  && HOME="$borrow_home" CODEX_CONFIG_DIR="$borrow_home/.codex" \
     CLAUDE_CONFIG_DIR="$borrow_claude_dir" \
     CODEX_CALL_LOG="$tmp/borrow-codex.log" CLAUDE_CALL_LOG="$tmp/borrow-claude.log" \
     PATH="$fake_bin:$PATH" \
     bash "$repository_root/bin/install" --global >/dev/null 2>&1 )

borrow_state="$borrow_claude_dir/plugins/installed_plugins.json"
# A project entry that HAS installPath, before a user entry that does not.
jq '.plugins["claudio-dr@dr-agents"] =
      ([{scope: "project", version: "0.0.1-project", installPath: "/project/claudio-dr"}]
       + (.plugins["claudio-dr@dr-agents"] | map(del(.installPath))))' \
  "$borrow_state" > "$borrow_state.tmp" && mv "$borrow_state.tmp" "$borrow_state"

# Guard the fixture: it proves nothing unless the user entry really lacks the
# field and the project entry really carries it.
[[ "$(jq -r 'first(.plugins["claudio-dr@dr-agents"][] | select(.scope == "user") | has("installPath"))' \
      "$borrow_state")" == "false" \
   && "$(jq -r '.plugins["claudio-dr@dr-agents"][0].installPath' \
      "$borrow_state")" == "/project/claudio-dr" ]] \
  || { echo "FAIL: could not stage a user entry missing installPath" >&2; exit 1; }

borrow_status="$( cd "$tmp" \
  && HOME="$borrow_home" CODEX_CONFIG_DIR="$borrow_home/.codex" \
     CLAUDE_CONFIG_DIR="$borrow_claude_dir" \
     CODEX_CALL_LOG="$tmp/borrow-codex.log" CLAUDE_CALL_LOG="$tmp/borrow-claude.log" \
     PATH="$fake_bin:$PATH" \
     bash "$repository_root/bin/install" --status 2>&1 )"

echo "$borrow_status" | grep -qF "/project/claudio-dr" \
  && { echo "FAIL: --status reported a project-scoped path as the global claudio-dr install" >&2
       echo "$borrow_status" >&2
       exit 1; }

echo "bin/install tests passed"
