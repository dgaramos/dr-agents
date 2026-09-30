#!/usr/bin/env bash
# Asserts the two copies of the top-level-string awk reader stay the same program.
#
# bin/stamp-workflow-versions:56 asks that its awk program be kept byte-identical
# to bin/install's. Nothing verified it, and by the time dr-agents#469 was
# reviewed they had already diverged -- both correct, which is exactly why the
# drift was invisible. This repository asserts byte-identity for the thread
# actions and for the guard across the six publisher definitions; this pair had
# no such assertion, so the comment was doing the work a check should do.
#
# The two cannot be literally byte-identical: bin/install sources nothing, on
# purpose, because --download installs it standalone, so each script carries its
# own copy and the invocation line differs -- the field comes from a parameter in
# one and is fixed in the other, and the file variable is named differently. Both
# differences are on the first and last line of the extracted program. Everything
# between them is the parser, and that is what must not drift.
set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
pass() { echo "ok: $*"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Extract the awk program out of a named function, minus its first and last
# line: the `awk -v field=...` invocation and the closing quote plus redirection.
extract_parser() {
  local file="$1" fn="$2" out="$3"
  awk -v fn="$fn" '
    $0 == fn "() {" { inside = 1 }
    inside { print }
    inside && /^\}$/ { exit }
  ' "$file" > "$tmp/fn.txt"
  grep -q "^$fn() {\$" "$tmp/fn.txt" \
    || { echo "FAIL: could not extract $fn from $file" >&2; exit 1; }
  # The awk program runs from the invocation line to the line closing the quote.
  awk "/awk -v field/ { inside = 1 }
       inside { print }
       inside && /^[[:space:]]*'/ && !/awk -v field/ { exit }" "$tmp/fn.txt" \
    | sed '1d;$d' | sed 's/^[[:space:]]*//' > "$out"
  [[ -s "$out" ]] || { echo "FAIL: extracted no awk program from $fn in $file" >&2; exit 1; }
}

readonly a="$tmp/install-parser.awk"
readonly b="$tmp/stamp-parser.awk"
extract_parser bin/install json_top_level_string "$a"
extract_parser bin/stamp-workflow-versions plugin_manifest_version "$b"

# A parser that shrank to nothing, or to a couple of lines, would compare equal
# for the wrong reason. It is a brace-tracking, escape-decoding walk; it cannot
# be short.
lines_a="$(wc -l < "$a" | tr -d ' ')"
if [[ "$lines_a" -lt 30 ]]; then
  fail "the extracted parser is only $lines_a lines; extraction is probably wrong"
else
  pass "extracted $lines_a lines of parser from each copy"
fi

if diff -u "$a" "$b" > "$tmp/diff.txt"; then
  pass "both copies of the top-level-string parser are the same program"
else
  fail "the two copies of the parser have drifted:"
  sed 's/^/      /' "$tmp/diff.txt" >&2
  echo "      bin/install:json_top_level_string and" >&2
  echo "      bin/stamp-workflow-versions:plugin_manifest_version must stay the" >&2
  echo "      same parser. Change both, or drop the claim at" >&2
  echo "      bin/stamp-workflow-versions:56 that they are kept identical." >&2
fi

# The comment making the claim must still be there: if someone removes it, this
# test is asserting a property nobody has declared.
if grep -q "byte-identical to bin/install" bin/stamp-workflow-versions; then
  pass "bin/stamp-workflow-versions still declares the property this test checks"
else
  fail "bin/stamp-workflow-versions no longer claims the parsers are kept identical"
fi

if [[ "$failures" -gt 0 ]]; then
  echo "$failures assertion(s) failed" >&2
  exit 1
fi
echo "shared awk reader tests passed"
