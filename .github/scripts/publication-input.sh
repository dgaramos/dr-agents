#!/usr/bin/env bash
# Input sanity checks shared by the script-backed publishers.
#
# Separate from publication-outcome.sh on purpose: that file states it only
# reports and changes no publication behavior. This one refuses to publish, so
# it does not belong there.
#
# Why this exists: dr-agents#372 was published with the body `/tmp/pr-body.md`.
# The caller wrote `gh workflow run -F body=/tmp/pr-body.md`, which sends the
# literal string; reading a file needs `-F body=@FILE`. Every layer then
# behaved correctly -- publish-pr.sh verified `.body == $BODY` and the observed
# body did equal the input -- so a PR merged with no description and nothing
# objected anywhere. The failure is silent by construction: the publisher
# cannot tell that the caller meant "the contents of this file", and the
# post-publication check compares against the same wrong value.
#
# The guard is deliberately narrow. It fires only when the ENTIRE body, once
# trimmed, is a single path-shaped token with no whitespace. A body that
# mentions a path, quotes one in backticks, or has any second word is real
# content and passes untouched. That shape has no legitimate counterexample:
# nobody publishes a PR, issue, review or reply whose whole body is one
# bare path.

# shellcheck shell=bash

# Refuse a body that is a bare filesystem path rather than its contents.
# Callers must define outcome_not_published (publication-outcome.sh).
require_body_contents() {
  local body="$1"
  local trimmed="${body#"${body%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"

  # Only a single-token body can be the mistake; anything with whitespace,
  # including any newline, is real content.
  case "$trimmed" in
    ''|*[[:space:]]*) return 0 ;;
  esac

  # A URL is a single token but is not a filesystem path.
  case "$trimmed" in
    *://*) return 0 ;;
  esac

  # Backticked or quoted content is deliberate prose about a path.
  case "$trimmed" in
    '`'*|\"*|\'*) return 0 ;;
  esac

  # A path shape: rooted, explicitly relative, containing a separator, or a
  # bare filename carrying a document extension.
  case "$trimmed" in
    /*|./*|../*|*/*|*.md|*.markdown|*.txt|*.json|*.yml|*.yaml)
      outcome_not_published \
        "body looks like a file path, not its contents: '$trimmed' -- pass the file's contents instead (gh: -F body=@FILE, or --body-file)"
      ;;
  esac
  return 0
}
