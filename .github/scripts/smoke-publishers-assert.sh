#!/usr/bin/env bash
# Decide whether a real publisher dispatch actually published (dr-agents#267).
#
# Why this asserts on GitHub rather than on the job's exit code:
#
# In dr-agents#258 the reply publisher posted its comment and *then* exited 1,
# because it compared a suffixless GraphQL login against an EXPECTED_AUTHOR in
# REST form. Exit code red, resource published. Any check that reads only the
# exit status reports that as a clean failure and leaves a stray comment behind;
# any check that reads only the resource reports it as a pass. This script reads
# both and requires them to agree.
#
# Why not the step summary: five of the six central definitions emit no typed
# publication outcome at all today (see the pull request for #267). Even once
# they do, a summary line is the publisher's self-report. The resource and its
# author are the observation.
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${EXPECTED_AUTHOR:?EXPECTED_AUTHOR is required}"
: "${CHECKS_JSON:?CHECKS_JSON is required}"

# A test seam: the default is the real query, and tests substitute a short
# token so a stubbed `gh` can be keyed on a readable argument string.
#
# Assigned in two steps deliberately. A `${VAR:-default}` whose default contains
# a literal `}` ends the expansion at that brace and appends the rest as literal
# text, which silently corrupted this query even when the variable was set.
thread_query='query($thread: ID!) { node(id: $thread) { ... on PullRequestReviewThread { isResolved } } }'
[[ -z "${SMOKE_THREAD_QUERY:-}" ]] || thread_query="$SMOKE_THREAD_QUERY"
readonly thread_query

jq -e 'type == "array" and length > 0 and all(.[];
        type == "object"
        and (.publisher | type == "string" and length > 0)
        and (.kind | type == "string" and length > 0)
        and (.ref | type == "string" and length > 0)
        and (.job_result | type == "string" and length > 0))' <<<"$CHECKS_JSON" >/dev/null \
  || { echo "invalid CHECKS_JSON" >&2; exit 1; }

summary() { [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && echo "$1" >>"$GITHUB_STEP_SUMMARY"; return 0; }

summary "### Publisher dispatch smoke test"
summary ""
summary "| publisher | job | observed | verdict |"
summary "| --- | --- | --- | --- |"

failures=0

while IFS= read -r check; do
  publisher="$(jq -r '.publisher' <<<"$check")"
  kind="$(jq -r '.kind' <<<"$check")"
  ref="$(jq -r '.ref' <<<"$check")"
  job_result="$(jq -r '.job_result' <<<"$check")"
  expect="$(jq -r '.expect // empty' <<<"$check")"
  [[ -n "$expect" ]] || expect="$EXPECTED_AUTHOR"

  # Observe what GitHub actually holds. A failed lookup means the publisher
  # produced no resource, which is a distinct verdict from producing a wrong
  # one -- the METADATA_HELPER and ref-skew shapes die before mutating.
  observed=""
  case "$kind" in
    issue)  observed="$(gh api "repos/${GITHUB_REPOSITORY}/issues/${ref}" --jq .user.login 2>/dev/null || true)" ;;
    pr)     observed="$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${ref}" --jq .user.login 2>/dev/null || true)" ;;
    review) observed="$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${ref}/reviews" --jq '.[-1].user.login' 2>/dev/null || true)" ;;
    reply)  observed="$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${ref}/comments" --jq '.[-1].user.login' 2>/dev/null || true)" ;;
    pr-labels)
      observed="$(gh api "repos/${GITHUB_REPOSITORY}/issues/${ref}" --jq '[.labels[].name]' 2>/dev/null || true)" ;;
    resolve)
      observed="$(gh api graphql -f query="$thread_query" -f thread="$ref" --jq .data.node.isResolved 2>/dev/null || true)" ;;
    *) echo "unsupported check kind: $kind" >&2; exit 1 ;;
  esac

  published=false
  [[ -n "$observed" && "$observed" != "null" ]] && published=true

  matches=false
  if [[ "$kind" == "pr-labels" ]]; then
    jq -e --arg want "$expect" 'index($want) != null' <<<"${observed:-[]}" >/dev/null 2>&1 && matches=true
  elif [[ "$observed" == "$expect" ]]; then
    matches=true
  fi

  green=false
  [[ "$job_result" == "success" ]] && green=true

  if [[ "$published" == true && "$green" != true ]]; then
    # The dr-agents#258 shape. Named explicitly, because a human has to go
    # remove the resource this left behind.
    echo "FAIL ${publisher}: published a resource but the job concluded '${job_result}'" >&2
    echo "  observed: ${observed}" >&2
    echo "  a resource exists over a red job; inspect and clean it up by hand" >&2
    summary "| ${publisher} | ${job_result} | \`${observed}\` | published-but-red |"
    failures=$((failures + 1))
    continue
  fi
  if [[ "$published" != true ]]; then
    echo "FAIL ${publisher}: no resource was produced (job concluded '${job_result}')" >&2
    summary "| ${publisher} | ${job_result} | none | not-published |"
    failures=$((failures + 1))
    continue
  fi
  if [[ "$matches" != true ]]; then
    echo "FAIL ${publisher}: expected '${expect}', observed '${observed}'" >&2
    summary "| ${publisher} | ${job_result} | \`${observed}\` | unexpected |"
    failures=$((failures + 1))
    continue
  fi
  summary "| ${publisher} | ${job_result} | \`${observed}\` | ok |"
  echo "ok ${publisher}: ${observed}"
done < <(jq -c '.[]' <<<"$CHECKS_JSON")

if (( failures > 0 )); then
  summary ""
  summary "**${failures} publisher check(s) failed.**"
  echo "${failures} publisher check(s) failed" >&2
  exit 1
fi
echo "all publisher checks passed"
