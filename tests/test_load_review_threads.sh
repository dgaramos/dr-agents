#!/usr/bin/env bash
# Offline tests for core/pr-review/scripts/load-review-threads.sh.
#
# The loader is the single place where a thread's GraphQL node id and its
# comments' REST databaseIds are produced together, so these cases pin the two
# properties that are easy to get silently wrong: every page is read (a thread
# on page 2 must appear), and `is_top_level` is derived from `replyTo` rather
# than from position in the list.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${LOAD_REVIEW_THREADS:-$root/core/pr-review/scripts/load-review-threads.sh}"

fail() { echo "FAIL: $*" >&2; exit 1; }
cases=0

# --- fake gh -------------------------------------------------------------
# Serves response-N.json for the Nth call, records every call, and can be told
# to fail from call N onwards. Counter-based rather than query-matching: the
# loader's call ORDER is part of what is under test, and a matcher would hide a
# page that was never requested.
new_gh() {
  FAKE_DIR="$(mktemp -d)"
  mkdir -p "$FAKE_DIR/bin"
  cat >"$FAKE_DIR/bin/gh" <<'GH'
#!/usr/bin/env bash
dir="$FAKE_GH_DIR"
n=$(( $(cat "$dir/count" 2>/dev/null || echo 0) + 1 ))
printf '%s' "$n" >"$dir/count"
printf '%s\n' "$*" >>"$dir/calls"
if [ -f "$dir/fail-from" ] && [ "$n" -ge "$(cat "$dir/fail-from")" ]; then
  echo "gh: simulated API failure" >&2
  exit 1
fi
[ -f "$dir/response-$n.json" ] || { echo "gh: no canned response $n" >&2; exit 1; }
cat "$dir/response-$n.json"
GH
  chmod +x "$FAKE_DIR/bin/gh"
  : >"$FAKE_DIR/calls"
}

run_loader() {
  set +e
  OUT="$(FAKE_GH_DIR="$FAKE_DIR" PATH="$FAKE_DIR/bin:$PATH" \
    bash "$script" "$@" 2>"$FAKE_DIR/stderr")"
  STATUS=$?
  set -e
  ERR="$(cat "$FAKE_DIR/stderr")"
}

# Build one reviewThreads page. $1 destination, $2 hasNextPage, $3 endCursor,
# $4.. raw thread node JSON objects.
page() {
  local dest="$1" has="$2" cursor="$3"; shift 3
  local nodes=""
  for node in "$@"; do nodes="${nodes:+$nodes,}$node"; done
  cat >"$dest" <<JSON
{"data":{"repository":{"pullRequest":{"reviewThreads":{
  "nodes":[$nodes],
  "pageInfo":{"hasNextPage":$has,"endCursor":"$cursor"}}}}}}
JSON
}

comment() { # id node author body replyTo-json created
  printf '{"databaseId":%s,"id":"%s","author":{"login":"%s"},"body":"%s","replyTo":%s,"createdAt":"%s"}' \
    "$1" "$2" "$3" "$4" "$5" "$6"
}
thread() { # node isResolved path line comments...
  local id="$1" res="$2" path="$3" line="$4"; shift 4
  local cs=""
  for c in "$@"; do cs="${cs:+$cs,}$c"; done
  printf '{"id":"%s","isResolved":%s,"path":"%s","line":%s,"comments":{"nodes":[%s],"pageInfo":{"hasNextPage":false,"endCursor":null}}}' \
    "$id" "$res" "$path" "$line" "$cs"
}

# A thread whose comment list is itself paged. Same shape as `thread`, but the
# comments pageInfo advertises another page, which sends the loader into its
# per-thread cursor walk.
thread_paged() { # node isResolved path line cursor comments...
  local id="$1" res="$2" path="$3" line="$4" cursor="$5"; shift 5
  local cs=""
  for c in "$@"; do cs="${cs:+$cs,}$c"; done
  printf '{"id":"%s","isResolved":%s,"path":"%s","line":%s,"comments":{"nodes":[%s],"pageInfo":{"hasNextPage":true,"endCursor":"%s"}}}' \
    "$id" "$res" "$path" "$line" "$cs" "$cursor"
}

# One `node(id:)` comments page, the response to a per-thread cursor walk.
comments_page() { # dest hasNextPage endCursor comments...
  local dest="$1" has="$2" cursor="$3"; shift 3
  local cs=""
  for c in "$@"; do cs="${cs:+$cs,}$c"; done
  cat >"$dest" <<JSON
{"data":{"node":{"comments":{
  "nodes":[$cs],
  "pageInfo":{"hasNextPage":$has,"endCursor":"$cursor"}}}}}
JSON
}

# --- A: pagination -------------------------------------------------------
# A thread that only exists on page 2 must survive. This is the case that fails
# the moment the cursor loop is dropped or the accumulator is overwritten.
new_gh
page "$FAKE_DIR/response-1.json" true "CUR1" \
  "$(thread T1 false src/a.sh 10 "$(comment 111 C1 alice "first" null 2024-01-01T00:00:00Z)")"
page "$FAKE_DIR/response-2.json" false null \
  "$(thread T2 true src/b.sh 20 "$(comment 222 C2 bob "second" null 2024-01-02T00:00:00Z)")"
run_loader owner/repo 7
[ "$STATUS" -eq 0 ] || fail "A: expected exit 0, got $STATUS ($ERR)"
[ "$(jq 'length' <<<"$OUT")" = 2 ] || fail "A: expected 2 threads, got $(jq -c . <<<"$OUT")"
[ "$(jq -r '[.[].thread_id]|sort|join(",")' <<<"$OUT")" = "T1,T2" ] \
  || fail "A: wrong thread ids: $(jq -c '[.[].thread_id]' <<<"$OUT")"
[ "$(jq '[.[]|select(.thread_id=="T1")]|length' <<<"$OUT")" = 1 ] \
  || fail "A: T1 appears more than once"
[ "$(jq -r '.[]|select(.thread_id=="T2")|.is_resolved' <<<"$OUT")" = true ] \
  || fail "A: T2 is_resolved not carried"
grep -q 'after=CUR1' "$FAKE_DIR/calls" || fail "A: page 2 not requested with the endCursor"
cases=$((cases + 1))

# --- B: reply vs top-level ----------------------------------------------
# is_top_level must come from replyTo, not from being first in the list.
new_gh
page "$FAKE_DIR/response-1.json" false null \
  "$(thread T1 false src/a.sh 10 \
      "$(comment 111 C1 alice "top" null 2024-01-01T00:00:00Z)" \
      "$(comment 112 C2 bob "reply" '{"id":"C1"}' 2024-01-01T01:00:00Z)")"
run_loader owner/repo 7
[ "$STATUS" -eq 0 ] || fail "B: expected exit 0, got $STATUS ($ERR)"
[ "$(jq -r '.[0].comments[0].is_top_level' <<<"$OUT")" = true ] || fail "B: first comment not top level"
[ "$(jq -r '.[0].comments[1].is_top_level' <<<"$OUT")" = false ] || fail "B: reply marked top level"
[ "$(jq -r '.[0].comments[1].database_id' <<<"$OUT")" = 112 ] || fail "B: reply database_id wrong"
[ "$(jq -r '.[0].comments[1].node_id' <<<"$OUT")" = C2 ] || fail "B: reply node_id wrong"
[ "$(jq -r '.[0].comments[1].author' <<<"$OUT")" = bob ] || fail "B: reply author wrong"
[ "$(jq -r '.[0].comments[1].body' <<<"$OUT")" = reply ] || fail "B: reply body wrong"
[ "$(jq -r '.[0].comments[1].created_at' <<<"$OUT")" = 2024-01-01T01:00:00Z ] || fail "B: created_at wrong"
cases=$((cases + 1))

# --- B2: a thread whose COMMENTS are paged ------------------------------
# Long threads are precisely the ones a duplicate-finding reply targets, so the
# per-thread cursor walk is the reason the loader exists -- yet every other
# fixture here advertises `hasNextPage:false` and never enters it. A loader that
# dropped the walk entirely would pass all of them and silently truncate the one
# thread that mattered.
new_gh
page "$FAKE_DIR/response-1.json" false null \
  "$(thread_paged T1 false src/a.sh 10 CCUR1 \
      "$(comment 111 C1 alice "first" null 2024-01-01T00:00:00Z)")"
comments_page "$FAKE_DIR/response-2.json" false null \
  "$(comment 112 C2 bob "second page" '{"id":"C1"}' 2024-01-01T02:00:00Z)"
run_loader owner/repo 7
[ "$STATUS" -eq 0 ] || fail "B2: expected exit 0, got $STATUS ($ERR)"
[ "$(jq '.[0].comments|length' <<<"$OUT")" = 2 ] \
  || fail "B2: expected both comment pages, got $(jq -c '.[0].comments' <<<"$OUT")"
[ "$(jq -r '[.[0].comments[].database_id]|join(",")' <<<"$OUT")" = "111,112" ] \
  || fail "B2: paged comments out of order or missing: $(jq -c '[.[0].comments[].database_id]' <<<"$OUT")"
[ "$(jq -r '.[0].comments[1].is_top_level' <<<"$OUT")" = false ] \
  || fail "B2: a comment from a later page lost its replyTo derivation"
grep -q 'after=CCUR1' "$FAKE_DIR/calls" \
  || fail "B2: the remaining comments were not requested with the thread endCursor"
grep -q 'thread=T1' "$FAKE_DIR/calls" \
  || fail "B2: the comments page was not requested for the thread node id"
cases=$((cases + 1))

# --- B3: a failure while paging a thread's comments ---------------------
# The all-or-nothing rule applies inside the per-thread walk too: a half-read
# thread must not reach stdout looking complete.
new_gh
page "$FAKE_DIR/response-1.json" false null \
  "$(thread_paged T1 false src/a.sh 10 CCUR1 \
      "$(comment 111 C1 alice "first" null 2024-01-01T00:00:00Z)")"
printf '2' >"$FAKE_DIR/fail-from"
run_loader owner/repo 7
[ "$STATUS" -ne 0 ] || fail "B3: expected non-zero exit when a comments page fails"
[ -z "$OUT" ] || fail "B3: stdout must be empty when a comments page fails, got: $OUT"
cases=$((cases + 1))

# --- C: gh failure on the FIRST call ------------------------------------
new_gh
printf '1' >"$FAKE_DIR/fail-from"
run_loader owner/repo 7
[ "$STATUS" -ne 0 ] || fail "C: expected non-zero exit on gh failure"
[ -z "$OUT" ] || fail "C: stdout must be empty on failure, got: $OUT"
cases=$((cases + 1))

# --- D: gh failure on a LATER page --------------------------------------
# The contract is "exits non-zero and prints nothing on stdout". A loader that
# streams each page as it arrives passes case C and fails here, which is the
# whole reason this case is separate.
new_gh
page "$FAKE_DIR/response-1.json" true "CUR1" \
  "$(thread T1 false src/a.sh 10 "$(comment 111 C1 alice "first" null 2024-01-01T00:00:00Z)")"
printf '2' >"$FAKE_DIR/fail-from"
run_loader owner/repo 7
[ "$STATUS" -ne 0 ] || fail "D: expected non-zero exit when page 2 fails"
[ -z "$OUT" ] || fail "D: stdout must be empty when a later page fails, got: $OUT"
cases=$((cases + 1))

# --- E: outdated thread with a null line --------------------------------
new_gh
page "$FAKE_DIR/response-1.json" false null \
  "$(thread T1 false src/gone.sh null "$(comment 111 C1 alice "stale" null 2024-01-01T00:00:00Z)")"
run_loader owner/repo 7
[ "$STATUS" -eq 0 ] || fail "E: expected exit 0 for an outdated thread, got $STATUS ($ERR)"
# Assert the KEY exists as well as being null: `jq -r .line` prints "null"
# for a missing key too, so the value assertion alone passes for an output
# that dropped the field entirely (found by mutating the implementation).
[ "$(jq -r '.[0]|has("line")' <<<"$OUT")" = true ] || fail "E: line key missing from output"
[ "$(jq -r '.[0].line' <<<"$OUT")" = null ] || fail "E: null line not preserved"
[ "$(jq -r '.[0].path' <<<"$OUT")" = src/gone.sh ] || fail "E: path not carried"
cases=$((cases + 1))

# --- F: usage ------------------------------------------------------------
new_gh
run_loader owner/repo
[ "$STATUS" -eq 2 ] || fail "F: expected usage exit 2, got $STATUS"
[ -z "$OUT" ] || fail "F: usage must not print to stdout"
cases=$((cases + 1))

echo "ok: test_load_review_threads.sh ($cases cases)"
