#!/usr/bin/env bash
set -euo pipefail

readonly claude_config="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
readonly call_log="${CLAUDE_CALL_LOG:?CLAUDE_CALL_LOG is required}"

printf '%s\n' "$*" >> "$call_log"

if [[ "${1:-}" == "plugin" && "${2:-}" == "marketplace" && "${3:-}" == "add" ]]; then
  readonly marketplace_root="${4:?marketplace root is required}"
  mkdir -p "$claude_config"
  printf '%s\n' "$marketplace_root" > "$claude_config/fake-marketplace-root"
  exit 0
fi

# The Claude Code CLI spells this `install`, where Codex spells it `add`. The
# divergence is the CLI's, not this catalog's; see tests/helpers/fake-codex.sh.
if [[ "${1:-}" == "plugin" && "${2:-}" == "install" && "${3:-}" == "claudio-dr@dr-agents" ]]; then
  readonly marketplace_root="$(< "$claude_config/fake-marketplace-root")"
  readonly source_dir="$marketplace_root/plugins/claudio-dr"
  readonly version="$(jq -r '.version' "$source_dir/.claude-plugin/plugin.json")"
  readonly destination="$claude_config/plugins/cache/dr-agents/claudio-dr/$version"
  mkdir -p "$(dirname "$destination")"
  rm -rf "$destination"
  cp -R "$source_dir" "$destination"
  # Claude Code records the installation in its own plugin state; bin/install
  # reads that state rather than guessing from the cache layout, so the fake
  # must write it too.
  mkdir -p "$claude_config/plugins"
  jq -n --arg path "$destination" --arg version "$version" \
    '{version: 2, plugins: {"claudio-dr@dr-agents": [{scope: "user", installPath: $path, version: $version}]}}' \
    > "$claude_config/plugins/installed_plugins.json"
  exit 0
fi

echo "fake claude: unsupported invocation: $*" >&2
exit 1
