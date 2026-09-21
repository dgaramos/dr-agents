#!/usr/bin/env bash
# Turn a validated review manifest into a tracked workflow dispatch.
#
# The publication this replaces was a hand-assembled `gh api --input` call. Two
# things made it fragile: the review body passed through shell interpolation on
# its way into the request, and nothing connected the dispatch to the run it
# created, so a failure was noticed by looking at the Actions tab.
#
# So: the request body is built entirely by `jq`, with the body read from the
# manifest via `--rawfile`/`--slurpfile` and never expanded by the shell, and
# the script locates the run it caused, watches it, and mirrors its conclusion
# in its own exit status.
#
# Dispatch is not idempotent -- a second one publishes a second review -- so a
# `.dispatched-<sha256>` marker beside the manifest makes an accidental repeat
# a refusal. The hash is over the manifest contents, so revising the review and
# dispatching again needs no override.
#
# Exit codes:
#   0  the run completed successfully
#   1  the dispatch call failed, the run failed, or this manifest was already
#      dispatched (a refusal: nothing was sent)
#   2  usage
#   3  the resulting run could not be identified -- unknown availability
set -euo pipefail

usage() {
  echo "usage: dispatch-review-manifest.sh MANIFEST_PATH WORKFLOW_FILE [--ref BRANCH] [--force]" >&2
  exit 2
}

[[ $# -ge 2 ]] || usage
manifest="$1"; workflow="$2"; shift 2
ref="main"
force=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref)   [[ $# -ge 2 ]] || usage; ref="$2"; shift 2 ;;
    --force) force=true; shift ;;
    *)       usage ;;
  esac
done
[[ -r "$manifest" ]] || { echo "not readable: $manifest" >&2; exit 2; }
jq -e . "$manifest" >/dev/null 2>&1 || { echo "not valid JSON: $manifest" >&2; exit 2; }

readonly repository="$(jq -r '.repository // empty' "$manifest")"
readonly pr_number="$(jq -r '.pr_number // empty' "$manifest")"
[[ "$repository" == */* ]] || { echo "manifest: repository must be OWNER/REPO" >&2; exit 2; }
[[ "$pr_number" =~ ^[1-9][0-9]*$ ]] || { echo "manifest: pr_number must be a positive integer" >&2; exit 2; }

# --- duplicate-dispatch marker ------------------------------------------
manifest_hash() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
readonly marker="$(dirname "$manifest")/.dispatched-$(manifest_hash "$manifest")"
if [[ -e "$marker" && "$force" != true ]]; then
  echo "already dispatched: this manifest was dispatched before (${marker})." >&2
  echo "Re-dispatching publishes a second review. Pass --force only if that is intended." >&2
  exit 1
fi

# --- request body --------------------------------------------------------
# Every value comes from the manifest through jq. Nothing below interpolates
# manifest content into a shell word, so a review body containing backticks,
# `$(...)`, quotes or emoji is transported unchanged. The three `*_json` inputs
# are compact JSON strings because that is the type a workflow input has.
readonly body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT
jq -n --arg ref "$ref" --slurpfile m "$manifest" '{
  ref: $ref,
  inputs: {
    pr_number: ($m[0].pr_number | tostring),
    event: $m[0].event,
    review_body: ($m[0].review_body // ""),
    reviewed_head_sha: $m[0].reviewed_head_sha,
    inline_comments_json: (($m[0].inline_comments // []) | tojson),
    replies_json: (($m[0].replies // []) | tojson),
    resolve_thread_ids_json: (($m[0].resolve_thread_ids // []) | tojson)
  }
}' >"$body_file"

# --- dispatch ------------------------------------------------------------
# The timestamp is taken BEFORE the dispatch so the run search cannot match a
# run that already existed.
readonly since="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if ! gh api --method POST \
     "repos/${repository}/actions/workflows/${workflow}/dispatches" \
     --input "$body_file" >/dev/null; then
  echo "dispatch failed: the workflow dispatch call did not succeed" >&2
  exit 1
fi
: >"$marker"

# --- locate the run ------------------------------------------------------
# A dispatched run takes a moment to appear, so poll rather than assume.
readonly attempts="${DISPATCH_RUN_LOOKUP_ATTEMPTS:-10}"
readonly delay="${DISPATCH_RUN_LOOKUP_DELAY:-3}"
runs="[]"
for _ in $(seq 1 "$attempts"); do
  runs="$(gh run list --workflow "$workflow" --branch "$ref" \
            --created ">=${since}" --limit 20 \
            --json databaseId,url,headBranch,status 2>/dev/null || echo '[]')"
  [[ "$(jq 'length' <<<"$runs")" -gt 0 ]] && break
  [[ "$delay" == 0 ]] || sleep "$delay"
done

candidates="$(jq -c --arg ref "$ref" '[.[] | select(.headBranch == $ref)]' <<<"$runs")"
count="$(jq 'length' <<<"$candidates")"

if [[ "$count" -gt 1 ]]; then
  # More than one run of this workflow started in the window. The publisher
  # echoes the pull request it acted on into its step summary, so keep only the
  # runs that name this one.
  matched="[]"
  while IFS= read -r run; do
    [[ -n "$run" ]] || continue
    id="$(jq -r '.databaseId' <<<"$run")"
    if gh run view "$id" --log 2>/dev/null | grep -qE "pr_number:?[[:space:]]*${pr_number}([^0-9]|$)"; then
      matched="$(jq -c --argjson r "$run" '. + [$r]' <<<"$matched")"
    fi
  done < <(jq -c '.[]' <<<"$candidates")
  candidates="$matched"
  count="$(jq 'length' <<<"$candidates")"
fi

if [[ "$count" -ne 1 ]]; then
  echo "unknown availability: the dispatch was accepted but its run could not be identified (${count} candidate runs)." >&2
  echo "Check the workflow's run list before dispatching again; a second dispatch would publish a second review." >&2
  exit 3
fi

readonly run_id="$(jq -r '.[0].databaseId' <<<"$candidates")"
readonly run_url="$(jq -r '.[0].url' <<<"$candidates")"
echo "run: ${run_url}"

# --- mirror the run's conclusion ----------------------------------------
if gh run watch "$run_id" --exit-status >/dev/null 2>&1; then
  echo "dispatch ok: ${run_url}"
  exit 0
fi
echo "run did not conclude successfully: ${run_url}" >&2
exit 1
