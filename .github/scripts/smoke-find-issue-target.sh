#!/usr/bin/env bash
# Find the permanent smoke target issue for one agent (dr-agents#267).
#
# Prints the issue number, or nothing at all when no target exists yet. An
# absent target is not an error: the caller passes the empty string to
# `reusable-publish-issue.yml`, which then takes its creation path.
#
# Why this is a script rather than three lines inline in the workflow: the
# comparison it performs is the one that broke the first real smoke run, and it
# is the same class as dr-agents#258 -- one login form compared against another.
# The surfaces genuinely disagree:
#
#   gh issue list --json author   ->  app/claudio-dr
#   REST .user.login              ->  claudio-dr[bot]
#
# So both sides are normalized (strip a leading `app/`, strip a trailing
# `[bot]`) rather than one literal being swapped for another, which would only
# move the bug to whichever surface changes next. `smoke-publishers-assert.sh`
# deliberately does NOT share this normalization: it reads the REST surface and
# compares full `<agent>-dr[bot]` logins, which was measured correct and is a
# stricter check where it can be afforded.
set -euo pipefail

: "${AGENT:?AGENT is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

readonly label="${SMOKE_TARGET_LABEL:-smoke-target}"

# --repo is required, not defensive: the jobs that call this run without a
# checkout, so gh has no git remote to infer the repository from. Omitting it
# is the other half of the failure that motivated this script.
gh issue list \
  --repo "$GITHUB_REPOSITORY" \
  --label "$label" \
  --state all \
  --limit 100 \
  --json number,author \
  --jq "
    [ .[]
      | select(
          (.author.login | sub(\"^app/\"; \"\") | sub(\"\\\\[bot\\\\]$\"; \"\"))
          == \"${AGENT}-dr\")
      | .number ]
    | sort
    | first
    // empty
  "
