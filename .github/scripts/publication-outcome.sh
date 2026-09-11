#!/usr/bin/env bash
# The typed publication outcome, shared by every script-backed publisher.
#
# `reusable-publish-issue.yml` has emitted this vocabulary inline since the
# migration; the five publishers backed by scripts emitted nothing at all, which
# dr-agents#270 recorded and this file closes. The wording here is taken from
# that definition deliberately, so a reader sees one vocabulary across all six.
#
# The contract:
#
#   not-published         Only before any mutation has been attempted. It is
#                         the sole outcome that entitles the reader to retry,
#                         so emitting it after a mutation is the worst possible
#                         error this file can make.
#   published-unverified  A resource exists but verification failed. The text
#                         must tell the reader NOT to republish. This is the
#                         dr-agents#258 shape, where the job exited 1 over a
#                         comment that had already been posted.
#   published-ok          The happy path.
#
# `outcome_resource` is emitted BEFORE any verdict, so a red job is never read
# as "nothing was published" -- that ordering is half the point of the exercise.
#
# This file only reports. It performs no GitHub call and changes no publication
# behavior: every caller keeps its own exit codes and its own control flow.

# shellcheck shell=bash

_outcome_heading="${PUBLICATION_HEADING:-publication}"
_outcome_heading_written=false

outcome_heading() { _outcome_heading="$1"; }

_outcome_summary() {
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] || return 0
  printf '%s\n' "$@" >>"$GITHUB_STEP_SUMMARY"
  return 0
}

_outcome_write_heading() {
  [[ "$_outcome_heading_written" == true ]] && return 0
  _outcome_summary "### ${_outcome_heading}" ""
  _outcome_heading_written=true
  return 0
}

# Name the resource that now exists. Call this as soon as an identifier is
# known and before any verification runs.
outcome_resource() {
  _outcome_write_heading
  _outcome_summary "- resource: $1"
}

# A detail worth recording that is not itself a verdict.
outcome_note() {
  _outcome_write_heading
  _outcome_summary "- $1"
}

outcome_not_published() {
  _outcome_write_heading
  _outcome_summary "- outcome: \`not-published\`" "- reason: $1"
  echo "not-published: $1" >&2
  exit 1
}

outcome_published_unverified() {
  _outcome_write_heading
  _outcome_summary \
    "- outcome: \`published-unverified\`" \
    "- $1" \
    "" \
    "The resource above **was published**. Do not republish it, and do not" \
    "publish it again under another identity. Inspect the resource and correct" \
    "the attribution in place."
  echo "published-unverified: $1; do not republish" >&2
  exit 1
}

outcome_published_ok() {
  _outcome_write_heading
  [[ $# -gt 0 ]] && _outcome_summary "- $1"
  _outcome_summary "- outcome: \`published-ok\`"
  return 0
}
