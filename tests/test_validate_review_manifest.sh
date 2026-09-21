#!/usr/bin/env bash
# Offline tests for core/pr-review/scripts/validate-review-manifest.sh.
#
# The point of the validator is that an invalid manifest costs one local run
# rather than one failed App dispatch, so the load-bearing property is that it
# reports EVERY failure in a single execution. A validator that exits on the
# first problem passes a naive single-fault test and still makes the user
# dispatch four times, which is why case A asserts all four failures together.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${VALIDATE_REVIEW_MANIFEST:-$root/core/pr-review/scripts/validate-review-manifest.sh}"

fail() { echo "FAIL: $*" >&2; exit 1; }
cases=0

readonly HEAD_SHA=1111111111111111111111111111111111111111
readonly STALE_SHA=2222222222222222222222222222222222222222

# --- fake gh -------------------------------------------------------------
# Routed by argument shape rather than call order: the validator is free to
# order its checks however it likes, and a counter-based fake would pin an
# ordering the contract does not require.
new_gh() {
  FAKE_DIR="$(mktemp -d)"
  mkdir -p "$FAKE_DIR/bin"
  cat >"$FAKE_DIR/bin/gh" <<'GH'
#!/usr/bin/env bash
dir="$FAKE_GH_DIR"
printf '%s\n' "$*" >>"$dir/calls"
if [ "$1" = "pr" ] && [ "$2" = "diff" ]; then cat "$dir/diff.txt"; exit 0; fi
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then cat "$dir/threads.json"; exit 0; fi
if [ "$1" = "api" ]; then
  case "$2" in
    */pulls/comments/*) cat "$dir/comment-${2##*/}.json"; exit 0 ;;
    */pulls/*)          cat "$dir/head.txt"; exit 0 ;;
  esac
fi
echo "gh: unexpected call: $*" >&2
exit 1
GH
  chmod +x "$FAKE_DIR/bin/gh"
  : >"$FAKE_DIR/calls"
  printf '%s\n' "$HEAD_SHA" >"$FAKE_DIR/head.txt"
  # Two hunks, so a line that is valid only in the second one exercises the
  # right-hand counter reset that a single-hunk fixture cannot reach.
  cat >"$FAKE_DIR/diff.txt" <<'DIFF'
diff --git a/src/a.sh b/src/a.sh
--- a/src/a.sh
+++ b/src/a.sh
@@ -1,3 +1,4 @@
 one
+two
 three
 four
@@ -20,3 +21,4 @@
 twenty
+twentyone
 twentytwo
 twentythree
DIFF
  cat >"$FAKE_DIR/threads.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{
  "nodes":[{"id":"THREAD_OURS"}],
  "pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
  # A top-level comment of this PR, and one that is itself a reply.
  cat >"$FAKE_DIR/comment-111.json" <<'JSON'
{"pull_request_url":"https://api.github.com/repos/owner/repo/pulls/7","in_reply_to_id":null}
JSON
  cat >"$FAKE_DIR/comment-222.json" <<'JSON'
{"pull_request_url":"https://api.github.com/repos/owner/repo/pulls/7","in_reply_to_id":111}
JSON
  cat >"$FAKE_DIR/comment-333.json" <<'JSON'
{"pull_request_url":"https://api.github.com/repos/owner/repo/pulls/99","in_reply_to_id":null}
JSON
}

manifest() { # $1 destination, stdin JSON
  cat >"$1"
}

run_validator() {
  set +e
  OUT="$(FAKE_GH_DIR="$FAKE_DIR" PATH="$FAKE_DIR/bin:$PATH" \
    bash "$script" "$1" 2>"$FAKE_DIR/stderr")"
  STATUS=$?
  set -e
  ERR="$(cat "$FAKE_DIR/stderr")"
  ALL="$OUT$ERR"
}

reports() {
  printf '%s' "$ALL" | grep -qF "$1" || fail "$2: missing report '$1' in: $ALL"
}

# --- A: four failures, one run ------------------------------------------
new_gh
m="$FAKE_DIR/m.json"
manifest "$m" <<JSON
{"repository":"owner/repo","pr_number":7,"event":"COMMENT",
 "reviewed_head_sha":"$STALE_SHA",
 "review_body":"summary",
 "inline_comments":[{"path":"src/a.sh","line":10,"body":"off-diff finding"}],
 "replies":[{"comment_id":222,"body":"still present"}],
 "resolve_thread_ids":["THREAD_ELSEWHERE"]}
JSON
run_validator "$m"
[ "$STATUS" -eq 1 ] || fail "A: expected exit 1, got $STATUS ($ALL)"
reports "src/a.sh:10" A
reports "reviewed_head_sha" A
reports "222" A
reports "THREAD_ELSEWHERE" A
# All four must come from ONE execution: assert each distinct failure category
# is named, not merely that the run failed.
[ "$(printf '%s' "$ALL" | grep -c 'manifest:')" -ge 4 ] \
  || fail "A: expected >=4 reported failures in one run, got: $ALL"
cases=$((cases + 1))

# --- B: valid manifest ---------------------------------------------------
new_gh
m="$FAKE_DIR/m.json"
manifest "$m" <<JSON
{"repository":"owner/repo","pr_number":7,"event":"COMMENT",
 "reviewed_head_sha":"$HEAD_SHA",
 "review_body":"summary",
 "inline_comments":[{"path":"src/a.sh","line":2,"body":"finding"}],
 "replies":[{"comment_id":111,"body":"still present"}],
 "resolve_thread_ids":["THREAD_OURS"]}
JSON
run_validator "$m"
[ "$STATUS" -eq 0 ] || fail "B: expected exit 0, got $STATUS ($ALL)"
[ "$OUT" = "manifest ok: inline=1 replies=1 resolutions=1" ] \
  || fail "B: wrong summary line: '$OUT'"
cases=$((cases + 1))

# --- C: read-only --------------------------------------------------------
# The validator sits immediately before dispatch; a mutating call here would
# publish something nobody authorized.
grep -qE -- '--method (POST|PATCH|PUT|DELETE)|mutation' "$FAKE_DIR/calls" \
  && fail "C: validator issued a mutating call: $(cat "$FAKE_DIR/calls")"
cases=$((cases + 1))

# --- D: multi-hunk boundaries -------------------------------------------
# 22 is a right-hand line of the SECOND hunk only. A parser that never resets
# its counter at the second @@ header rejects it; one that treats any line
# number below the file length as valid accepts line 10. Both directions are
# asserted, because each alone is passed by a different broken parser.
new_gh
m="$FAKE_DIR/m.json"
manifest "$m" <<JSON
{"repository":"owner/repo","pr_number":7,"event":"COMMENT",
 "reviewed_head_sha":"$HEAD_SHA","review_body":"summary",
 "inline_comments":[{"path":"src/a.sh","line":22,"body":"second hunk"}],
 "replies":[],"resolve_thread_ids":[]}
JSON
run_validator "$m"
[ "$STATUS" -eq 0 ] || fail "D: line 22 (second hunk) should be valid: $ALL"
new_gh
m="$FAKE_DIR/m.json"
manifest "$m" <<JSON
{"repository":"owner/repo","pr_number":7,"event":"COMMENT",
 "reviewed_head_sha":"$HEAD_SHA","review_body":"summary",
 "inline_comments":[{"path":"src/a.sh","line":10,"body":"between hunks"}],
 "replies":[],"resolve_thread_ids":[]}
JSON
run_validator "$m"
[ "$STATUS" -eq 1 ] || fail "D: line 10 (between hunks) should be rejected"
reports "src/a.sh:10" D
cases=$((cases + 1))

# --- D2: context lines are commentable ----------------------------------
# An unchanged context line inside a hunk is on the right-hand side and GitHub
# accepts a comment on it. A parser that advances the counter for context lines
# but only records added ones passes every other case here and silently rejects
# a legitimate finding, so it needs a case of its own. Line 21 also proves the
# second hunk's counter starts on its context line, not on its first addition.
for ctx_line in 3 21; do
  new_gh
  m="$FAKE_DIR/m.json"
  manifest "$m" <<JSON
{"repository":"owner/repo","pr_number":7,"event":"COMMENT",
 "reviewed_head_sha":"$HEAD_SHA","review_body":"summary",
 "inline_comments":[{"path":"src/a.sh","line":$ctx_line,"body":"context finding"}],
 "replies":[],"resolve_thread_ids":[]}
JSON
  run_validator "$m"
  [ "$STATUS" -eq 0 ] || fail "D2: context line $ctx_line should be commentable: $ALL"
done
cases=$((cases + 1))

# --- E: reply target on another pull request -----------------------------
new_gh
m="$FAKE_DIR/m.json"
manifest "$m" <<JSON
{"repository":"owner/repo","pr_number":7,"event":"COMMENT",
 "reviewed_head_sha":"$HEAD_SHA","review_body":"summary",
 "inline_comments":[],"replies":[{"comment_id":333,"body":"wrong pr"}],
 "resolve_thread_ids":[]}
JSON
run_validator "$m"
[ "$STATUS" -eq 1 ] || fail "E: foreign reply target should be rejected"
reports "333" E
cases=$((cases + 1))

# --- F: shape and event --------------------------------------------------
new_gh
m="$FAKE_DIR/m.json"
manifest "$m" <<JSON
{"repository":"owner/repo","pr_number":7,"event":"APPROVE",
 "reviewed_head_sha":"$HEAD_SHA","review_body":"summary",
 "inline_comments":[{"path":"src/a.sh","line":2}],
 "replies":[],"resolve_thread_ids":[]}
JSON
run_validator "$m"
[ "$STATUS" -eq 1 ] || fail "F: invalid shape and event should be rejected"
reports "inline_comments" F
reports "event" F
cases=$((cases + 1))

# --- H: an added line whose text begins with "++" ------------------------
# In a unified diff a content line reading `++ item` is emitted as `+++ item`,
# which is indistinguishable from a file header by prefix alone. A parser that
# tests the prefix without knowing it is inside a hunk adopts `item` as the
# current path, and every later right-hand line of that file is recorded under
# the wrong one -- so a legitimate anchor is rejected with a message naming a
# path the diff never contained.
#
# Both directions are asserted in the SAME diff: a fix that simply stopped
# treating `+++` as a header would pass a fixture that only re-checks the
# previously rejected line, so line 99 must still be rejected.
new_gh
cat >"$FAKE_DIR/diff.txt" <<'DIFF'
diff --git a/src/b.sh b/src/b.sh
--- a/src/b.sh
+++ b/src/b.sh
@@ -1,2 +1,4 @@
 one
+++ item
+after
 four
DIFF
m="$FAKE_DIR/m.json"
manifest "$m" <<JSON
{"repository":"owner/repo","pr_number":7,"event":"COMMENT",
 "reviewed_head_sha":"$HEAD_SHA","review_body":"summary",
 "inline_comments":[{"path":"src/b.sh","line":3,"body":"after the ++ line"}],
 "replies":[],"resolve_thread_ids":[]}
JSON
run_validator "$m"
[ "$STATUS" -eq 0 ] \
  || fail "H: a right-hand line after a '++'-prefixed addition should be valid: $ALL"
new_gh
cat >"$FAKE_DIR/diff.txt" <<'DIFF'
diff --git a/src/b.sh b/src/b.sh
--- a/src/b.sh
+++ b/src/b.sh
@@ -1,2 +1,4 @@
 one
+++ item
+after
 four
DIFF
m="$FAKE_DIR/m.json"
manifest "$m" <<JSON
{"repository":"owner/repo","pr_number":7,"event":"COMMENT",
 "reviewed_head_sha":"$HEAD_SHA","review_body":"summary",
 "inline_comments":[{"path":"src/b.sh","line":99,"body":"not in the diff"}],
 "replies":[],"resolve_thread_ids":[]}
JSON
run_validator "$m"
[ "$STATUS" -eq 1 ] || fail "H: line 99 is not in the diff and must still be rejected"
reports "src/b.sh:99" H
cases=$((cases + 1))

# --- G: unreadable manifest ---------------------------------------------
new_gh
run_validator "$FAKE_DIR/does-not-exist.json"
[ "$STATUS" -eq 2 ] || fail "G: expected usage exit 2 for a missing manifest, got $STATUS"
cases=$((cases + 1))

echo "ok: test_validate_review_manifest.sh ($cases cases)"
