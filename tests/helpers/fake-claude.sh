#!/usr/bin/env bash
set -euo pipefail

claude_config="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
call_log="${CLAUDE_CALL_LOG:?CLAUDE_CALL_LOG is required}"

printf '%s\n' "$*" >> "$call_log"

state_file="$claude_config/plugins/installed_plugins.json"

# The version Claude Code currently has recorded for claudio-dr@dr-agents, or
# empty when nothing is recorded. bin/install reads this same state, so the
# fake must be the only thing that writes it.
recorded_version() {
  [[ -f "$state_file" ]] || return 0
  jq -r '(.plugins["claudio-dr@dr-agents"] // []) | map(.version // empty) | first // empty' \
    "$state_file" 2>/dev/null || true
}

# Materialise the cache copy and record the installation, the way the real CLI
# does when it actually performs one.
record_install() {
  local marketplace_root source_dir version destination
  marketplace_root="$(< "$claude_config/fake-marketplace-root")"
  source_dir="$marketplace_root/plugins/claudio-dr"
  version="$(jq -r '.version' "$source_dir/.claude-plugin/plugin.json")"
  destination="$claude_config/plugins/cache/dr-agents/claudio-dr/$version"
  mkdir -p "$(dirname "$destination")"
  rm -rf "$destination"
  cp -R "$source_dir" "$destination"
  mkdir -p "$claude_config/plugins"
  jq -n --arg path "$destination" --arg version "$version" \
    '{version: 2, plugins: {"claudio-dr@dr-agents": [{scope: "user", installPath: $path, version: $version}]}}' \
    > "$state_file"
  printf '%s\n' "$version"
}

catalog_version() {
  local marketplace_root
  marketplace_root="$(< "$claude_config/fake-marketplace-root")"
  jq -r '.version' "$marketplace_root/plugins/claudio-dr/.claude-plugin/plugin.json"
}

if [[ "${1:-}" == "plugin" && "${2:-}" == "marketplace" && "${3:-}" == "add" ]]; then
  marketplace_root="${4:?marketplace root is required}"
  mkdir -p "$claude_config"
  printf '%s\n' "$marketplace_root" > "$claude_config/fake-marketplace-root"
  exit 0
fi

# `marketplace update` re-reads a configured marketplace from its source.
# bin/install runs it under --force, where a stale snapshot would silently
# install the catalog as it stood before the pull.
if [[ "${1:-}" == "plugin" && "${2:-}" == "marketplace" && "${3:-}" == "update" ]]; then
  [[ -f "$claude_config/fake-marketplace-root" ]] \
    || { echo "fake claude: no marketplace to update" >&2; exit 1; }
  exit 0
fi

# The Claude Code CLI spells this `install`, where Codex spells it `add`. The
# divergence is the CLI's, not this catalog's; see tests/helpers/fake-codex.sh.
#
# dr-agents#455: `install` is a NO-OP on an already-installed plugin. It does
# not re-record the version, and the real CLI says so in its own output,
# naming `plugin update` as the command that does:
#
#   ✔ Plugin "claudio-dr@dr-agents" is already installed (scope: user) — it
#     loads in place from <path>, so edits there take effect at the next
#     session start or /reload-plugins; `claude plugin update
#     claudio-dr@dr-agents` re-records its version, 0.1.41 to 0.1.43
#
# This fake previously re-recorded unconditionally, which modelled a CLI that
# was never wrong and left the stale-version regression untestable. Modelling
# the no-op is the point: without it the fix cannot be observed failing.
if [[ "${1:-}" == "plugin" && "${2:-}" == "install" && "${3:-}" == "claudio-dr@dr-agents" ]]; then
  existing="$(recorded_version)"
  if [[ -n "$existing" ]]; then
    echo "Plugin \"claudio-dr@dr-agents\" is already installed (scope: user) — it loads in place; \`claude plugin update claudio-dr@dr-agents\` re-records its version, $existing to $(catalog_version)"
    exit 0
  fi
  record_install >/dev/null
  exit 0
fi

# dr-agents#455: `plugin update` is what re-records the version. It fails when
# the plugin is not installed, which is why bin/install cannot simply replace
# the `install` dispatch with this one.
if [[ "${1:-}" == "plugin" && "${2:-}" == "update" && "${3:-}" == "claudio-dr@dr-agents" ]]; then
  existing="$(recorded_version)"
  if [[ -z "$existing" ]]; then
    echo "fake claude: Failed to update plugin \"claudio-dr@dr-agents\": Plugin \"claudio-dr\" not found" >&2
    exit 1
  fi
  updated="$(record_install)"
  if [[ "$existing" == "$updated" ]]; then
    echo "claudio-dr is already at the latest version ($updated)."
  else
    echo "Plugin \"claudio-dr\" updated from $existing to $updated for scope user."
  fi
  exit 0
fi

echo "fake claude: unsupported invocation: $*" >&2
exit 1
