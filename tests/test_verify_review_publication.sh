#!/usr/bin/env bash
# Offline tests for core/pr-review/scripts/verify-review-publication.sh.
#
# The behaviour under test is a distinction, not a count: when a reply is posted
# over REST the platform creates an empty review to contain it, and those shells
# must be tolerated while a genuine second review must not be. So the suite
# pairs every "tolerated" case with the smallest change that must still fail --
# one more shell than replies, and a shell that carries content.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${VERIFY_REVIEW_PUBLICATION:-$root/core/pr-review/scripts/verify-review-publication.sh}"

fail() { echo "FAIL: $*" >&2; exit 1; }
cases=0

readonly ACTOR="reviewer-app[bot]"
readonly OTHER="someone-else"
readonly HEAD=1111111111111111111111111111111111111111
readonly OLD_HEAD=2222222222222222222222222222222222222222
readonly BODY="## Summary"

new_gh() {
  FAKE_DIR="$(mktemp -d)"
  mkdir -p "$FAKE_DIR/bin"
  cat >"$FAKE_DIR/bin/gh" <<'GH'
#!/usr/bin/env bash
dir="$FAKE_GH_DIR"
printf '%s\n' "$*" >>"$dir/calls"
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then cat "$dir/threads.json"; exit 0; fi
if [ "$1" = "api" ]; then
  case "$2" in
    */reviews)  cat "$dir/reviews.json"; exit 0 ;;
    */comments) cat "$dir/comments.json"; exit 0 ;;
  esac
fi
echo "gh: unexpected call: $*" >&2
exit 1
GH
  chmod +x "$FAKE_DIR/bin/gh"
  : >"$FAKE_DIR/calls"
  echo '[]' >"$FAKE_DIR/reviews.json"
  echo '[]' >"$FAKE_DIR/comments.json"
  cat >"$FAKE_DIR/threads.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{
  "nodes":[{"id":"THREAD_OURS","isResolved":true}],
  "pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
}

# reviews.json entries. $1 id $2 author $3 body $4 commit
review() { printf '{"id":%s,"user":{"login":"%s"},"body":"%s","state":"COMMENTED","commit_id":"%s"}' "$1" "$2" "$3" "$4"; }
set_reviews() { local j=""; for r in "$@"; do j="${j:+$j,}$r"; done; echo "[$j]" >"$FAKE_DIR/reviews.json"; }

# comments.json entries. $1 id $2 author $3 review_id $4 in_reply_to (or null)
comment() { printf '{"id":%s,"user":{"login":"%s"},"pull_request_review_id":%s,"in_reply_to_id":%s,"body":"c"}' "$1" "$2" "$3" "$4"; }
set_comments() { local j=""; for c in "$@"; do j="${j:+$j,}$c"; done; echo "[$j]" >"$FAKE_DIR/comments.json"; }

write_manifest() { # $1 dest, $2 replies JSON, $3 resolve ids JSON, $4 body
  jq -n --arg body "${4-$BODY}" --argjson replies "$2" --argjson threads "$3" '{
    repository: "owner/repo", pr_number: 7, event: "COMMENT",
    reviewed_head_sha: "'"$HEAD"'", review_body: $body,
    inline_comments: [], replies: $replies, resolve_thread_ids: $threads
  }' >"$1"
}

run_verify() {
  set +e
  OUT="$(FAKE_GH_DIR="$FAKE_DIR" PATH="$FAKE_DIR/bin:$PATH" \
    bash "$script" "$1" "$2" 2>"$FAKE_DIR/stderr")"
  STATUS=$?
  set -e
  ERR="$(cat "$FAKE_DIR/stderr")"
  ALL="$OUT$ERR"
}

# --- A: review plus two replies and two shells --------------------------
new_gh
set_reviews "$(review 10 "$ACTOR" "$BODY" "$HEAD")" \
            "$(review 11 "$ACTOR" "" "$HEAD")" \
            "$(review 12 "$ACTOR" "" "$HEAD")"
set_comments "$(comment 501 "$ACTOR" 11 111)" "$(comment 502 "$ACTOR" 12 222)"
m="$FAKE_DIR/m.json"
write_manifest "$m" '[{"comment_id":111,"body":"r1"},{"comment_id":222,"body":"r2"}]' '["THREAD_OURS"]'
run_verify "$m" "$ACTOR"
[ "$STATUS" -eq 0 ] || fail "A: expected pass, got $STATUS ($ALL)"
printf '%s' "$ALL" | grep -qF 'published-ok' || fail "A: expected published-ok: $ALL"
printf '%s' "$ALL" | grep -qF 'implicit reply shells: 2' \
  || fail "A: shell count not reported as 2: $ALL"
cases=$((cases + 1))

# --- B: one more shell than replies must fail ---------------------------
# The boundary, not a round number: 2 shells for 2 replies passes above, 3 does
# not. Without this pair the tolerance could be unbounded and case A would not
# notice.
new_gh
set_reviews "$(review 10 "$ACTOR" "$BODY" "$HEAD")" \
            "$(review 11 "$ACTOR" "" "$HEAD")" \
            "$(review 12 "$ACTOR" "" "$HEAD")" \
            "$(review 13 "$ACTOR" "" "$HEAD")"
set_comments "$(comment 501 "$ACTOR" 11 111)" "$(comment 502 "$ACTOR" 12 222)"
m="$FAKE_DIR/m.json"
write_manifest "$m" '[{"comment_id":111,"body":"r1"},{"comment_id":222,"body":"r2"}]' '["THREAD_OURS"]'
run_verify "$m" "$ACTOR"
[ "$STATUS" -eq 1 ] || fail "B: three shells for two replies must fail, got $STATUS"
printf '%s' "$ALL" | grep -qF 'published-unverified' || fail "B: expected published-unverified: $ALL"
cases=$((cases + 1))

# --- C: an extra review that carries content ----------------------------
# Same count as case A, but the extra review has a body. It is a real review
# event, not a container the platform made, and must be reported as such.
new_gh
set_reviews "$(review 10 "$ACTOR" "$BODY" "$HEAD")" \
            "$(review 11 "$ACTOR" "a second opinion" "$HEAD")"
set_comments
m="$FAKE_DIR/m.json"
write_manifest "$m" '[]' '[]'
run_verify "$m" "$ACTOR"
[ "$STATUS" -eq 1 ] || fail "C: extra non-empty review must fail, got $STATUS"
printf '%s' "$ALL" | grep -qF 'unexpected additional review' \
  || fail "C: expected 'unexpected additional review': $ALL"
cases=$((cases + 1))

# --- C2: a body-less review that carries inline comments ----------------
# Body-less is not the same as empty. A review with no body but with inline
# findings is a real review, and counting it as a shell would hide a duplicate
# publication.
new_gh
set_reviews "$(review 10 "$ACTOR" "$BODY" "$HEAD")" \
            "$(review 11 "$ACTOR" "" "$HEAD")"
set_comments "$(comment 601 "$ACTOR" 11 null)"
m="$FAKE_DIR/m.json"
write_manifest "$m" '[]' '[]'
run_verify "$m" "$ACTOR"
[ "$STATUS" -eq 1 ] || fail "C2: a body-less review with inline comments must not count as a shell"
printf '%s' "$ALL" | grep -qF 'unexpected additional review' \
  || fail "C2: expected 'unexpected additional review': $ALL"
cases=$((cases + 1))

# --- D: wrong actor ------------------------------------------------------
new_gh
set_reviews "$(review 10 "$OTHER" "$BODY" "$HEAD")"
set_comments
m="$FAKE_DIR/m.json"
write_manifest "$m" '[]' '[]'
run_verify "$m" "$ACTOR"
[ "$STATUS" -eq 1 ] || fail "D: a review by another actor must not verify"
cases=$((cases + 1))

# --- E: the review is on an older head ----------------------------------
new_gh
set_reviews "$(review 10 "$ACTOR" "$BODY" "$OLD_HEAD")"
set_comments
m="$FAKE_DIR/m.json"
write_manifest "$m" '[]' '[]'
run_verify "$m" "$ACTOR"
[ "$STATUS" -eq 1 ] || fail "E: a review on an older head must not verify"
cases=$((cases + 1))

# --- F: body mismatch ----------------------------------------------------
new_gh
set_reviews "$(review 10 "$ACTOR" "a different summary" "$HEAD")"
set_comments
m="$FAKE_DIR/m.json"
write_manifest "$m" '[]' '[]'
run_verify "$m" "$ACTOR"
[ "$STATUS" -eq 1 ] || fail "F: a divergent review body must not verify"
cases=$((cases + 1))

# --- G: a reply is missing ----------------------------------------------
new_gh
set_reviews "$(review 10 "$ACTOR" "$BODY" "$HEAD")" "$(review 11 "$ACTOR" "" "$HEAD")"
set_comments "$(comment 501 "$ACTOR" 11 111)"
m="$FAKE_DIR/m.json"
write_manifest "$m" '[{"comment_id":111,"body":"r1"},{"comment_id":222,"body":"r2"}]' '[]'
run_verify "$m" "$ACTOR"
[ "$STATUS" -eq 1 ] || fail "G: a missing reply must not verify"
printf '%s' "$ALL" | grep -qF '222' || fail "G: the missing reply target should be named: $ALL"
cases=$((cases + 1))

# --- H: a reply by the wrong author -------------------------------------
new_gh
set_reviews "$(review 10 "$ACTOR" "$BODY" "$HEAD")" "$(review 11 "$ACTOR" "" "$HEAD")"
set_comments "$(comment 501 "$OTHER" 11 111)"
m="$FAKE_DIR/m.json"
write_manifest "$m" '[{"comment_id":111,"body":"r1"}]' '[]'
run_verify "$m" "$ACTOR"
[ "$STATUS" -eq 1 ] || fail "H: a reply by another author must not verify"
cases=$((cases + 1))

# --- I: an unresolved thread --------------------------------------------
new_gh
set_reviews "$(review 10 "$ACTOR" "$BODY" "$HEAD")"
set_comments
cat >"$FAKE_DIR/threads.json" <<'JSON'
{"data":{"repository":{"pullRequest":{"reviewThreads":{
  "nodes":[{"id":"THREAD_OURS","isResolved":false}],
  "pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
m="$FAKE_DIR/m.json"
write_manifest "$m" '[]' '["THREAD_OURS"]'
run_verify "$m" "$ACTOR"
[ "$STATUS" -eq 1 ] || fail "I: an unresolved thread must not verify"
printf '%s' "$ALL" | grep -qF 'THREAD_OURS' || fail "I: the unresolved thread should be named: $ALL"
cases=$((cases + 1))

# --- J: an empty review body with inline findings -----------------------
# A pass may publish findings with no summary. The review is then legitimately
# body-less, and the inline set is what proves it is real.
new_gh
set_reviews "$(review 10 "$ACTOR" "" "$HEAD")"
set_comments "$(comment 601 "$ACTOR" 10 null)"
m="$FAKE_DIR/m.json"
write_manifest "$m" '[]' '[]' ""
run_verify "$m" "$ACTOR"
[ "$STATUS" -eq 0 ] || fail "J: a body-less review with inline findings should verify ($ALL)"
cases=$((cases + 1))

# --- K: usage ------------------------------------------------------------
new_gh
run_verify "$FAKE_DIR/missing.json" "$ACTOR"
[ "$STATUS" -eq 2 ] || fail "K: expected usage exit 2, got $STATUS"
cases=$((cases + 1))

echo "ok: test_verify_review_publication.sh ($cases cases)"
