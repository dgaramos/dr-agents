#!/usr/bin/env bash
# Offline tests for core/pr-review/scripts/dispatch-review-manifest.sh.
#
# The publication this script replaces was a hand-typed `gh api --input` call,
# and the failure mode it exists to prevent is a review body mangled on its way
# to the workflow. So the central case captures the payload the fake `gh`
# actually received and compares the transported body byte for byte against the
# source file -- asserting on the transported artifact, never on the script's
# own text, which would pass for a script that builds the body correctly and
# then sends something else.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${DISPATCH_REVIEW_MANIFEST:-$root/core/pr-review/scripts/dispatch-review-manifest.sh}"

fail() { echo "FAIL: $*" >&2; exit 1; }
cases=0
bt='`'   # a literal backtick kept in a variable, so no quoting accident in a
         # test body can reopen command substitution (this bit the catalog once)

new_gh() {
  FAKE_DIR="$(mktemp -d)"
  mkdir -p "$FAKE_DIR/bin"
  cat >"$FAKE_DIR/bin/gh" <<'GH'
#!/usr/bin/env bash
dir="$FAKE_GH_DIR"
printf '%s\n' "$*" >>"$dir/calls"
case "$1" in
  api)
    prev=""
    for a in "$@"; do
      if [ "$prev" = "--input" ]; then cp "$a" "$dir/captured.json"; fi
      prev="$a"
    done
    printf 'dispatch\n' >>"$dir/dispatches"
    exit "$(cat "$dir/dispatch-status" 2>/dev/null || echo 0)"
    ;;
  run)
    case "$2" in
      list)  cat "$dir/runs.json" ;;
      view)  cat "$dir/log-$3.txt" 2>/dev/null || echo "" ;;
      watch) exit "$(cat "$dir/watch-status" 2>/dev/null || echo 0)" ;;
    esac
    exit 0
    ;;
esac
echo "gh: unexpected call: $*" >&2
exit 1
GH
  chmod +x "$FAKE_DIR/bin/gh"
  : >"$FAKE_DIR/calls"
  : >"$FAKE_DIR/dispatches"
  echo '[{"databaseId":900,"url":"https://example.test/runs/900","headBranch":"main","status":"completed"}]' \
    >"$FAKE_DIR/runs.json"
}

# A body full of every character that has ever survived a shell round trip
# incorrectly. Written through a file so the test source itself never needs to
# quote it a second time.
write_manifest() {
  local dest="$1"
  local body_file="$FAKE_DIR/body.txt"
  {
    printf 'Summary with a %scode span%s and $(rm -rf /) and ${HOME}\n' "$bt" "$bt"
    printf 'A "double quoted" phrase and a '"'"'single quoted'"'"' one.\n'
    printf 'Backslash \\ and newline handling, emoji: a rocket and a check.\n'
    printf 'Unicode: \xf0\x9f\x9a\x80 \xe2\x9c\x85 \xc3\xa9\xc3\xa8\xc3\xaa\n'
    printf 'Trailing whitespace matters too:   \n'
  } >"$body_file"
  jq -n --rawfile body "$body_file" '{
    repository: "owner/repo",
    pr_number: 7,
    event: "COMMENT",
    reviewed_head_sha: "1111111111111111111111111111111111111111",
    review_body: $body,
    inline_comments: [{path: "src/a.sh", line: 2, body: "finding"}],
    replies: [{comment_id: 111, body: "still present"}],
    resolve_thread_ids: ["THREAD_OURS"]
  }' >"$dest"
}

run_dispatch() {
  set +e
  OUT="$(FAKE_GH_DIR="$FAKE_DIR" PATH="$FAKE_DIR/bin:$PATH" \
    DISPATCH_RUN_LOOKUP_ATTEMPTS=2 DISPATCH_RUN_LOOKUP_DELAY=0 \
    bash "$script" "$@" 2>"$FAKE_DIR/stderr")"
  STATUS=$?
  set -e
  ERR="$(cat "$FAKE_DIR/stderr")"
  ALL="$OUT$ERR"
}

dispatch_count() { grep -c . "$FAKE_DIR/dispatches" || true; }

# --- A: byte-for-byte transport -----------------------------------------
new_gh
work="$(mktemp -d)"; m="$work/manifest.json"
write_manifest "$m"
run_dispatch "$m" publish-review.yml
[ "$STATUS" -eq 0 ] || fail "A: expected exit 0, got $STATUS ($ALL)"
[ -f "$FAKE_DIR/captured.json" ] || fail "A: no --input payload was captured"

# The transported body, extracted from what gh actually received, must equal
# the source file exactly -- not merely contain it, and not merely be non-empty.
jq -r '.inputs.review_body' "$FAKE_DIR/captured.json" >"$FAKE_DIR/transported.txt"
jq -r '.review_body' "$m" >"$FAKE_DIR/source.txt"
cmp -s "$FAKE_DIR/source.txt" "$FAKE_DIR/transported.txt" \
  || fail "A: review_body was altered in transport:
$(diff "$FAKE_DIR/source.txt" "$FAKE_DIR/transported.txt" || true)"

# The three *_json inputs must arrive as compact JSON STRINGS, because the
# workflow input type is string. Sending them as objects is the mistake that
# looks correct locally and fails at the API.
for key in inline_comments_json replies_json resolve_thread_ids_json; do
  [ "$(jq -r ".inputs.${key} | type" "$FAKE_DIR/captured.json")" = string ] \
    || fail "A: ${key} was not transported as a string"
done
[ "$(jq -r '.inputs.inline_comments_json | fromjson | .[0].path' "$FAKE_DIR/captured.json")" = src/a.sh ] \
  || fail "A: inline_comments_json did not round-trip"
[ "$(jq -r '.inputs.replies_json | fromjson | .[0].comment_id' "$FAKE_DIR/captured.json")" = 111 ] \
  || fail "A: replies_json did not round-trip"
[ "$(jq -r '.inputs.pr_number' "$FAKE_DIR/captured.json")" = 7 ] || fail "A: pr_number missing"
[ "$(jq -r '.inputs.reviewed_head_sha' "$FAKE_DIR/captured.json")" = 1111111111111111111111111111111111111111 ] \
  || fail "A: reviewed_head_sha missing"
[ "$(jq -r '.ref' "$FAKE_DIR/captured.json")" = main ] || fail "A: default ref should be main"
printf '%s' "$ALL" | grep -qF 'https://example.test/runs/900' || fail "A: run URL not printed"
cases=$((cases + 1))

# --- B: marker refusal ---------------------------------------------------
# The marker is written by case A's successful dispatch, so this case also
# proves the marker is created rather than only honoured.
ls "$work"/.dispatched-* >/dev/null 2>&1 || fail "B: no .dispatched marker was written"
new_gh
run_dispatch "$m" publish-review.yml
[ "$STATUS" -ne 0 ] || fail "B: expected refusal for an already-dispatched manifest"
[ "$(dispatch_count)" -eq 0 ] || fail "B: refusal happened AFTER dispatching"
printf '%s' "$ALL" | grep -qiF 'already dispatched' || fail "B: refusal reason not stated: $ALL"
cases=$((cases + 1))

# --- C: --force overrides ------------------------------------------------
new_gh
run_dispatch "$m" publish-review.yml --force
[ "$STATUS" -eq 0 ] || fail "C: --force should dispatch, got $STATUS ($ALL)"
[ "$(dispatch_count)" -eq 1 ] || fail "C: expected exactly one dispatch, got $(dispatch_count)"
cases=$((cases + 1))

# --- D: a changed manifest is a different marker -------------------------
# The marker is keyed on the manifest's content hash, so editing the review and
# dispatching again must be allowed without --force.
new_gh
jq '.review_body = "a revised summary"' "$m" >"$work/manifest2.json"
run_dispatch "$work/manifest2.json" publish-review.yml
[ "$STATUS" -eq 0 ] || fail "D: a modified manifest should not be blocked by the old marker ($ALL)"
cases=$((cases + 1))

# --- E: run concludes other than success ---------------------------------
new_gh
work2="$(mktemp -d)"; m2="$work2/manifest.json"; write_manifest "$m2"
echo 1 >"$FAKE_DIR/watch-status"
run_dispatch "$m2" publish-review.yml
[ "$STATUS" -eq 1 ] || fail "E: expected exit 1 for a failed run, got $STATUS"
printf '%s' "$ALL" | grep -qF 'https://example.test/runs/900' \
  || fail "E: the run URL must be printed when the run fails: $ALL"
cases=$((cases + 1))

# --- F: no run found -----------------------------------------------------
new_gh
work3="$(mktemp -d)"; m3="$work3/manifest.json"; write_manifest "$m3"
echo '[]' >"$FAKE_DIR/runs.json"
run_dispatch "$m3" publish-review.yml
[ "$STATUS" -eq 3 ] || fail "F: expected exit 3 when no run is found, got $STATUS"
printf '%s' "$ALL" | grep -qiF 'unknown availability' || fail "F: expected 'unknown availability': $ALL"
cases=$((cases + 1))

# --- G: ambiguous runs ---------------------------------------------------
# Two candidate runs whose logs both echo this pr_number cannot be told apart.
new_gh
work4="$(mktemp -d)"; m4="$work4/manifest.json"; write_manifest "$m4"
cat >"$FAKE_DIR/runs.json" <<'JSON'
[{"databaseId":900,"url":"https://example.test/runs/900","headBranch":"main","status":"completed"},
 {"databaseId":901,"url":"https://example.test/runs/901","headBranch":"main","status":"completed"}]
JSON
echo 'pr_number: 7' >"$FAKE_DIR/log-900.txt"
echo 'pr_number: 7' >"$FAKE_DIR/log-901.txt"
run_dispatch "$m4" publish-review.yml
[ "$STATUS" -eq 3 ] || fail "G: expected exit 3 for ambiguous runs, got $STATUS"
printf '%s' "$ALL" | grep -qiF 'unknown availability' || fail "G: expected 'unknown availability': $ALL"
cases=$((cases + 1))

# --- H: disambiguation by pr_number --------------------------------------
# Same two runs, but only one echoes this pull request. That one must be used,
# which is what makes case G an ambiguity rather than a hard limit.
new_gh
work5="$(mktemp -d)"; m5="$work5/manifest.json"; write_manifest "$m5"
cat >"$FAKE_DIR/runs.json" <<'JSON'
[{"databaseId":900,"url":"https://example.test/runs/900","headBranch":"main","status":"completed"},
 {"databaseId":901,"url":"https://example.test/runs/901","headBranch":"main","status":"completed"}]
JSON
echo 'pr_number: 99' >"$FAKE_DIR/log-900.txt"
echo 'pr_number: 7'  >"$FAKE_DIR/log-901.txt"
run_dispatch "$m5" publish-review.yml
[ "$STATUS" -eq 0 ] || fail "H: expected the unambiguous run to be selected, got $STATUS ($ALL)"
printf '%s' "$ALL" | grep -qF 'https://example.test/runs/901' \
  || fail "H: selected the wrong run: $ALL"
cases=$((cases + 1))

# --- I: dispatch itself fails -------------------------------------------
new_gh
work6="$(mktemp -d)"; m6="$work6/manifest.json"; write_manifest "$m6"
echo 1 >"$FAKE_DIR/dispatch-status"
run_dispatch "$m6" publish-review.yml
[ "$STATUS" -eq 1 ] || fail "I: expected exit 1 when the dispatch call fails, got $STATUS"
ls "$work6"/.dispatched-* >/dev/null 2>&1 \
  && fail "I: a marker was written for a dispatch that never happened"
cases=$((cases + 1))

# --- J: usage ------------------------------------------------------------
new_gh
run_dispatch "$m"
[ "$STATUS" -eq 2 ] || fail "J: expected usage exit 2, got $STATUS"
run_dispatch "$FAKE_DIR/missing.json" publish-review.yml
[ "$STATUS" -eq 2 ] || fail "J: expected usage exit 2 for a missing manifest, got $STATUS"
cases=$((cases + 1))

echo "ok: test_dispatch_review_manifest.sh ($cases cases)"
