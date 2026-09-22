#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: resolve-target.sh [REFERENCE] [--from-specs-repository VALUE]" >&2
  exit 2
}

explicit_seen=false
explicit_reference=""
specs_seen=false
specs_repository=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-specs-repository)
      [[ "$specs_seen" == false && $# -ge 2 ]] || usage
      specs_seen=true
      specs_repository="$2"
      shift 2
      ;;
    --*) usage ;;
    *)
      [[ "$explicit_seen" == false ]] || usage
      explicit_seen=true
      explicit_reference="$1"
      shift
      ;;
  esac
done
[[ "$explicit_seen" == false || -n "$explicit_reference" ]] || usage
[[ "$specs_seen" == false || -n "$specs_repository" ]] || usage

normalized_host=""
normalized_target=""
normalized_kind="repo"
normalized_number=""
lowercase() { printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]'; }
normalize_reference() {
  local value="$1" host="" owner="" repository="" kind="repo" number=""
  if [[ "$value" =~ ^https://([^/]+)/([^/]+)/([^/]+)/(pull|issues)/([1-9][0-9]*)/?$ ]]; then
    host="${BASH_REMATCH[1]}"; owner="${BASH_REMATCH[2]}"; repository="${BASH_REMATCH[3]}"
    [[ "${BASH_REMATCH[4]}" == pull ]] && kind="pr" || kind="issue"
    number="${BASH_REMATCH[5]}"
  elif [[ "$value" =~ ^https://([^/]+)/([^/]+)/([^/]+)/?$ ]]; then
    host="${BASH_REMATCH[1]}"; owner="${BASH_REMATCH[2]}"; repository="${BASH_REMATCH[3]}"
  elif [[ "$value" =~ ^git@([^:]+):([^/]+)/(.+)$ ]]; then
    host="${BASH_REMATCH[1]}"; owner="${BASH_REMATCH[2]}"; repository="${BASH_REMATCH[3]}"
  elif [[ "$value" =~ ^ssh://git@([^/]+)/([^/]+)/(.+)$ ]]; then
    host="${BASH_REMATCH[1]}"; owner="${BASH_REMATCH[2]}"; repository="${BASH_REMATCH[3]}"
  elif [[ "$value" =~ ^([^/]+)/([^/#]+)#([1-9][0-9]*)$ ]]; then
    host="github.com"; owner="${BASH_REMATCH[1]}"; repository="${BASH_REMATCH[2]}"
    kind="number"; number="${BASH_REMATCH[3]}"
  elif [[ "$value" =~ ^([^/]+)/([^/#]+)$ ]]; then
    host="github.com"; owner="${BASH_REMATCH[1]}"; repository="${BASH_REMATCH[2]}"
  else
    return 1
  fi

  repository="${repository%.git}"
  [[ "$owner" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1
  [[ "$repository" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 1
  [[ "$host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || return 1
  normalized_host="$(lowercase "$host")"
  normalized_target="$owner/$repository"
  normalized_kind="$kind"
  normalized_number="$number"
}

source=""
reference_value=""
if [[ "$explicit_seen" == true ]]; then
  source="explicit"
  reference_value="$explicit_reference"
elif [[ "$specs_seen" == true ]]; then
  source="specs-repository"
  reference_value="$specs_repository"
else
  source="cwd"
  if ! repository_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || ! reference_value="$(git -C "$repository_root" remote get-url origin 2>/dev/null)"; then
    echo "target unknown: no explicit reference and cwd has no origin" >&2
    exit 4
  fi
fi

normalize_reference "$reference_value" || {
  echo "malformed repository reference: $reference_value" >&2
  exit 2
}
target_host="$normalized_host"
target="$normalized_target"
reference_kind="$normalized_kind"
reference_number="$normalized_number"
target_key="$(lowercase "$target_host/$target")"

cwd_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
checkout=""
checkout_evidence="none"
if [[ -n "$cwd_root" ]]; then
  cwd_origin="$(git -C "$cwd_root" remote get-url origin 2>/dev/null || true)"
  if [[ -n "$cwd_origin" ]] && normalize_reference "$cwd_origin"; then
    if [[ "$(lowercase "$normalized_host/$normalized_target")" == "$target_key" ]]; then
      checkout="$(cd "$cwd_root" && pwd -P)"
      checkout_evidence="cwd-origin"
    fi
  fi
fi

if [[ -z "$checkout" ]]; then
  if [[ -n "${DR_AGENTS_REPO_ROOTS+x}" ]]; then
    roots_value="$DR_AGENTS_REPO_ROOTS"
  elif [[ -n "$cwd_root" ]]; then
    roots_value="$(dirname "$cwd_root")"
  else
    roots_value="$(dirname "$PWD")"
  fi

  candidates=()
  candidate_evidence=()
  IFS=':' read -r -a roots <<<"$roots_value"
  for root in "${roots[@]}"; do
    [[ -n "$root" ]] || continue
    if [[ ! -d "$root" ]]; then
      echo "warning: repository root does not exist: $root" >&2
      continue
    fi
    root="$(cd "$root" && pwd -P)"
    while IFS= read -r directory; do
      [[ -n "$directory" && -e "$directory/.git" ]] || continue
      directory="$(cd "$directory" && pwd -P)"
      [[ -z "$cwd_root" || "$directory" != "$(cd "$cwd_root" && pwd -P)" ]] || continue
      origin="$(git -C "$directory" remote get-url origin 2>/dev/null || true)"
      [[ -n "$origin" ]] || continue
      if normalize_reference "$origin" \
        && [[ "$(lowercase "$normalized_host/$normalized_target")" == "$target_key" ]]; then
        candidates+=("$directory")
        candidate_evidence+=("root-scan:$root")
      fi
    done < <(find -L "$root" -mindepth 1 -maxdepth 1 -type d -print | LC_ALL=C sort)
  done

  if [[ "${#candidates[@]}" -gt 1 ]]; then
    echo "ambiguous checkouts for $target:" >&2
    printf '%s\n' "${candidates[@]}" >&2
    exit 3
  elif [[ "${#candidates[@]}" -eq 1 ]]; then
    checkout="${candidates[0]}"
    checkout_evidence="${candidate_evidence[0]}"
  fi
fi

if [[ -n "$checkout" ]]; then mode="checkout"; else mode="remote-only"; fi
if [[ -n "$reference_number" ]]; then number_json="$reference_number"; else number_json="null"; fi
jq -cn \
  --arg target "$target" \
  --arg host "$target_host" \
  --arg source "$source" \
  --arg kind "$reference_kind" \
  --argjson number "$number_json" \
  --arg checkout "$checkout" \
  --arg evidence "$checkout_evidence" \
  --arg mode "$mode" \
  '{target:$target,host:$host,source:$source,reference:{kind:$kind,number:$number},checkout:(if $checkout == "" then null else $checkout end),checkout_evidence:$evidence,mode:$mode}'
