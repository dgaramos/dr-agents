#!/usr/bin/env bash
set -euo pipefail

[[ $# == 2 ]] || { echo "usage: select-publisher.sh OWNER/REPO WORKFLOW_PATH" >&2; exit 2; }
repository="$1"
workflow_path="$2"
if ! workflows="$(gh api --paginate "repos/${repository}/actions/workflows?per_page=100")"; then
  echo "Publisher availability unknown; failed discovery does not authorize personal fallback" >&2
  exit 1
fi
matches="$(jq -se --arg path "$workflow_path" '
  if all(.[]; (.workflows | type) == "array") then
    [.[].workflows[] | select(.path == $path)]
  else error("invalid workflow discovery response") end' <<<"$workflows")"
count="$(jq length <<<"$matches")"
if [[ "$count" == 1 ]]; then
  state="$(jq -er '.[0].state' <<<"$matches")"
  case "$state" in
    active)
      jq -n --arg workflow "$workflow_path" '{route:"app", workflow:$workflow, reason:"matching workflow is active; dispatch App publisher"}'
      exit 0 ;;
    disabled_manually|disabled_inactivity) reason="matching workflow is disabled: $state" ;;
    *) echo "Publisher state is unknown; personal fallback is not authorized" >&2; exit 1 ;;
  esac
elif [[ "$count" == 0 ]]; then
  reason="matching workflow is absent from successful repository workflow enumeration"
else
  echo "Ambiguous publisher discovery; personal fallback is not authorized" >&2
  exit 1
fi
actor="$(gh api user --jq .login)"
[[ -n "$actor" && "$actor" != null ]] || { echo "No authenticated fallback actor" >&2; exit 1; }
jq -n --arg actor "$actor" --arg reason "$reason" '{route:"personal", actor:$actor, reason:$reason}'
