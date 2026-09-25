#!/usr/bin/env bash
set -euo pipefail

readonly codex_config="${CODEX_CONFIG_DIR:-${HOME}/.codex}"
readonly call_log="${CODEX_CALL_LOG:?CODEX_CALL_LOG is required}"

printf '%s\n' "$*" >> "$call_log"

if [[ "${1:-}" == "plugin" && "${2:-}" == "marketplace" && "${3:-}" == "add" ]]; then
  readonly marketplace_root="${4:?marketplace root is required}"
  mkdir -p "$codex_config"
  printf '%s\n' "$marketplace_root" > "$codex_config/fake-marketplace-root"
  exit 0
fi

if [[ "${1:-}" == "plugin" && "${2:-}" == "add" && "${3:-}" == "cody-dr@dr-agents" ]]; then
  readonly marketplace_root="$(< "$codex_config/fake-marketplace-root")"
  readonly source_dir="$marketplace_root/plugins/cody-dr"
  readonly version="$(jq -r '.version' "$source_dir/.codex-plugin/plugin.json")"
  readonly destination="$codex_config/plugins/cache/dr-agents/cody-dr/$version"
  mkdir -p "$(dirname "$destination")"
  cp -R "$source_dir" "$destination"
  printf '%s\n' "$version" > "$codex_config/fake-registered-cody-version"
  exit 0
fi

if [[ "${1:-}" == "plugin" && "${2:-}" == "list" && "${3:-}" == "--json" ]]; then
  if [[ ! -f "$codex_config/fake-registered-cody-version" ]]; then
    printf '%s\n' '{"installed":[],"available":[]}'
    exit 0
  fi
  readonly registered_version="$(< "$codex_config/fake-registered-cody-version")"
  jq -n --arg version "$registered_version" '{
    installed: [{
      pluginId: "cody-dr@dr-agents",
      name: "cody-dr",
      marketplaceName: "dr-agents",
      version: $version,
      installed: true,
      enabled: true
    }],
    available: []
  }'
  exit 0
fi

echo "fake codex: unsupported invocation: $*" >&2
exit 1
