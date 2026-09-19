#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="${PUBLICATION_INPUT_LIB:-$root/.github/scripts/publication-input.sh}"

fail() { echo "FAIL: $*" >&2; exit 1; }
cases=0
bt='`'   # a literal backtick, kept in a variable so no quoting trick can
         # reopen command substitution in a test body (it did once).

# Run the guard in a subshell so its `exit 1` does not end the suite.
run() {
  set +e
  CASE_STDERR="$(bash -c '
    . "$1"
    outcome_not_published() { echo "not-published: $1" >&2; exit 1; }
    require_body_contents "$2"
  ' _ "$lib" "$1" 2>&1 >/dev/null)"
  CASE_STATUS=$?
  set -e
}

rejects() {
  local name="$1" body="$2"
  run "$body"
  [ "$CASE_STATUS" -ne 0 ] || fail "$name: expected reject, was accepted (body=$body)"
  printf '%s' "$CASE_STDERR" | grep -qF 'looks like a file path' \
    || fail "$name: rejected for the wrong reason: $CASE_STDERR"
  cases=$((cases + 1))
}

accepts() {
  local name="$1" body="$2"
  run "$body"
  [ "$CASE_STATUS" -eq 0 ] || fail "$name: expected accept, got $CASE_STATUS ($CASE_STDERR)"
  cases=$((cases + 1))
}

# A: the exact regression -- an absolute path to a Markdown body file.
rejects A "/tmp/pr-body.md"
# B: a relative path, the other natural shape of the same mistake.
rejects B "pr-body.md"
# C: ./ and ../ forms.
rejects C "./body.md"
rejects D "../bodies/body.txt"
# E: a path with no extension is still a path when it is the entire body.
rejects E "/tmp/pr-body"

# F: a real body that merely MENTIONS a path must pass. This is the case a
#    careless `grep` would break, and the reason the guard is anchored to the
#    whole single-line body rather than searching within it.
accepts F "Fixes the loader so it reads /tmp/pr-body.md correctly."
# G: a one-word body is legitimate, if unusual.
accepts G "Typo."
# H: a real multi-line body whose FIRST line is a path-like word.
accepts H "$(printf 'config.md\n\nRewrites the config document.')"
# I: a normal Markdown body.
accepts I "$(printf '## Context\n\nSomething broke.\n')"
# J: a body that is a bare URL is not a file path.
accepts J "https://example.test/spec.md"
# K: a code-fenced path is real content.
accepts K '`/tmp/pr-body.md`'
# L: empty body is not this guard's job -- callers already require non-empty.
accepts L ""
# M: leading/trailing whitespace around a path is still the mistake.
rejects M "  /tmp/pr-body.md  "

# The issue and issue-comment publishers perform no checkout by design, so they
# carry an inline copy of this guard instead of sourcing the library. Two copies
# of one rule is exactly the drift CLAUDE.md warns about, so assert parity by
# extracting the inline `case` and running it over the same table rather than
# trusting the copies to stay aligned by hand.
for wf in .github/workflows/reusable-publish-issue.yml \
          .github/workflows/reusable-publish-issue-comment.yml; do
  [ -f "$root/$wf" ] || fail "parity: missing $wf"
  probe="$(mktemp)"
  {
    echo 'not_published() { echo "not-published: $1" >&2; exit 1; }'
    echo 'BODY="$1"'
    sed -n '/^ *case "${BODY#/,/^ *esac$/p' "$root/$wf" | sed 's/^          //'
    echo 'echo accepted'
  } >"$probe"
  bash -n "$probe" || fail "parity: $wf inline guard is not valid shell"

  inline_verdict() {
    set +e
    bash "$probe" "$1" >/dev/null 2>&1
    local st=$?
    set -e
    return $st
  }
  library_verdict() {
    set +e
    bash -c '. "$1"; outcome_not_published() { exit 1; }; require_body_contents "$2"' \
      _ "$lib" "$1" >/dev/null 2>&1
    local st=$?
    set -e
    return $st
  }

  for probe_body in \
    "/tmp/pr-body.md" "pr-body.md" "./body.md" "../b/body.txt" "/tmp/pr-body" \
    "notes.yml" "data.json" \
    "Fixes /tmp/pr-body.md correctly." "Typo." "## Context" \
    "https://example.test/spec.md" "${bt}/tmp/pr-body.md${bt}" ""; do
    inline_verdict "$probe_body" && i=accept || i=reject
    library_verdict "$probe_body" && l=accept || l=reject
    [ "$i" = "$l" ] || fail "parity: $wf disagrees with the library on '"'"'$probe_body'"'"' (inline=$i library=$l)"
    cases=$((cases + 1))
  done
  rm -f "$probe"
done

echo "publication input tests passed ($cases cases)"
