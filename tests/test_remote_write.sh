#!/usr/bin/env bash
set -euo pipefail

# Covers core/target-resolution/scripts/remote-write.sh (dr-agents#357, #336).
# The real gh is never invoked: a fake records method, endpoint and the body
# passed through --input, so the call sequence and the byte-for-byte commit
# message are observable properties rather than claims.

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly writer="$repository_root/core/target-resolution/scripts/remote-write.sh"
temporary_directory="$(mktemp -d)"
readonly temporary_directory
trap 'rm -rf "$temporary_directory"' EXIT

fail() { echo "not ok: $*" >&2; exit 1; }

readonly fake_bin="$temporary_directory/bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/gh" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
method=GET
endpoint=""
input=""
shift # api
while [[ $# -gt 0 ]]; do
  case "$1" in
    --method|-X) method="$2"; shift 2 ;;
    --input) input="$2"; shift 2 ;;
    -H|--header|--jq|-q|-f|-F) shift 2 ;;
    -*) shift ;;
    *) endpoint="$1"; shift ;;
  esac
done
printf '%s %s\n' "$method" "$endpoint" >>"$GH_LOG"
call_index="$(wc -l <"$GH_LOG" | tr -d ' ')"
if [[ -n "$input" && "$input" != "-" ]]; then
  cp "$input" "$GH_CALLS/$call_index.json"
elif [[ -n "$input" ]]; then
  cat >"$GH_CALLS/$call_index.json"
fi
mkdir -p "$GH_STATE"
if [[ "$method" == POST && "$endpoint" == */git/commits ]]; then
  printf '%s\n' "$(jq -r '.parents[0]' "$GH_CALLS/$call_index.json")" \
    >"$GH_STATE/parent-of-${FAKE_COMMIT_SHA:-commitsha}"
fi
# The fake models the two server behaviors that matter here: gh reports an
# absent ref as `HTTP 404` and every other failure with its own status, and
# GitHub refuses a `force:false` ref move unless the new commit descends from
# the ref's current head. Without that ancestry check the fake would accept a
# PATCH the real API rejects, which is exactly how the diverged-parent defect
# stayed invisible.
readonly head_sha="${FAKE_HEAD_SHA:-headsha}"
case "$endpoint" in
  */git/ref/heads/feature)
    if [[ -n "${FAKE_PRECHECK_STATUS:-}" ]]; then
      echo "gh: Internal Server Error (HTTP $FAKE_PRECHECK_STATUS)" >&2
      exit 1
    fi
    [[ "${FAKE_HEAD_EXISTS:-0}" == 1 ]] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
    printf '{"object":{"sha":"%s"}}\n' "$head_sha" ;;
  */git/ref/heads/main) echo '{"object":{"sha":"base123"}}' ;;
  */git/commits/base123) echo '{"tree":{"sha":"tree123"}}' ;;
  */git/commits/"$head_sha") echo '{"tree":{"sha":"headtree"}}' ;;
  */git/commits/*) echo "fake gh: unexpected commit read $endpoint" >&2; exit 1 ;;
  */git/blobs) echo "{\"sha\":\"blob$call_index\"}" ;;
  */git/trees) echo '{"sha":"newtree"}' ;;
  */git/commits)
    jq -e --arg parent "${FAKE_EXPECT_PARENT:-}" \
      'if $parent == "" then true else .parents == [$parent] end' \
      "$GH_CALLS/$call_index.json" >/dev/null \
      || { echo "fake gh: commit parent mismatch" >&2; exit 1; }
    printf '{"sha":"%s"}\n' "${FAKE_COMMIT_SHA:-commitsha}" ;;
  */git/refs) echo '{"ref":"refs/heads/feature"}' ;;
  */git/refs/heads/feature)
    # A non-force ref move must fast-forward: the pushed commit has to descend
    # from the ref's current head. The fake knows each created commit's parent.
    pushed="$(jq -r '.sha' "$GH_CALLS/$call_index.json")"
    forced="$(jq -r '.force' "$GH_CALLS/$call_index.json")"
    parent="$(cat "$GH_STATE/parent-of-$pushed" 2>/dev/null || echo '')"
    if [[ "$forced" != true && "$parent" != "$head_sha" ]]; then
      echo "gh: Update is not a fast forward (HTTP 422)" >&2
      exit 1
    fi
    echo '{"ref":"refs/heads/feature"}' ;;
  *) echo "fake gh: unexpected endpoint $endpoint" >&2; exit 1 ;;
esac
FAKE
chmod +x "$fake_bin/gh"
export PATH="$fake_bin:$PATH"

readonly first_file="$temporary_directory/first.md"
readonly second_file="$temporary_directory/second.md"
printf 'first content\nwith a trailing newline\n' >"$first_file"
printf 'second\x00-ish binary safe content\n' >"$second_file"

readonly manifest="$temporary_directory/manifest.json"
jq -n --arg a "$first_file" --arg b "$second_file" \
  '[{path:"docs/first.md",file:$a},{path:"docs/second.md",file:$b}]' >"$manifest"

# A message deliberately full of shell-hostile bytes: backticks, a command
# substitution, quotes and an emoji must survive to the commit unchanged.
readonly message_file="$temporary_directory/message.txt"
cat >"$message_file" <<'MESSAGE'
feat(core): `remote-write.sh` for $(git rev-parse HEAD) writes

Quotes "double" and 'single', a backslash \ and an emoji 🚀.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MESSAGE

run_writer() {
  local log_directory="$temporary_directory/$1"
  shift
  mkdir -p "$log_directory/calls" "$log_directory/state"
  GH_LOG="$log_directory/log" GH_CALLS="$log_directory/calls" \
    GH_STATE="$log_directory/state" \
    "$writer" "$@"
}

# --- happy path -------------------------------------------------------------
output="$(run_writer create o/r main feature "$manifest" "$message_file")"

readonly create_log="$temporary_directory/create/log"
expected_log="$(cat <<'LOG'
GET repos/o/r/git/ref/heads/feature
GET repos/o/r/git/ref/heads/main
GET repos/o/r/git/commits/base123
POST repos/o/r/git/blobs
POST repos/o/r/git/blobs
POST repos/o/r/git/trees
POST repos/o/r/git/commits
POST repos/o/r/git/refs
LOG
)"
[[ "$(cat "$create_log")" == "$expected_log" ]] || {
  echo "--- actual ---" >&2; cat "$create_log" >&2
  fail "call sequence must be pre-check, base ref, base commit, blobs, tree, commit, ref"
}

jq -e '.commit == "commitsha" and .ref == "refs/heads/feature" and .files == 2' <<<"$output" >/dev/null \
  || fail "summary output: $output"

readonly calls="$temporary_directory/create/calls"
jq -r '.content' "$calls/4.json" | base64 --decode | cmp -s - "$first_file" \
  || fail "first blob content must round-trip byte-for-byte"
jq -e '.encoding == "base64"' "$calls/4.json" >/dev/null || fail "blobs must be uploaded as base64"
jq -r '.content' "$calls/5.json" | base64 --decode | cmp -s - "$second_file" \
  || fail "second blob content must round-trip byte-for-byte"

jq -e '.base_tree == "tree123"
  and (.tree | length) == 2
  and (.tree[0] | .path == "docs/first.md" and .mode == "100644" and .type == "blob" and .sha == "blob4")
  and (.tree[1] | .path == "docs/second.md" and .sha == "blob5")' "$calls/6.json" >/dev/null \
  || fail "tree request: $(cat "$calls/6.json")"

jq -e '.tree == "newtree" and .parents == ["base123"]' "$calls/7.json" >/dev/null \
  || fail "commit request: $(cat "$calls/7.json")"
jq -j '.message' "$calls/7.json" | cmp -s - "$message_file" \
  || fail "commit message must be byte-for-byte equal to the message file"

jq -e '.ref == "refs/heads/feature" and .sha == "commitsha"' "$calls/8.json" >/dev/null \
  || fail "ref creation request: $(cat "$calls/8.json")"

# --- failure path: the branch already exists and --update was not passed -----
set +e
existing_output="$(FAKE_HEAD_EXISTS=1 run_writer existing o/r main feature "$manifest" "$message_file" 2>"$temporary_directory/existing.err")"
existing_status=$?
set -e
[[ "$existing_status" -ne 0 ]] || fail "an existing branch without --update must exit non-zero (got: $existing_output)"
if grep -q '^POST' "$temporary_directory/existing/log"; then
  fail "no write may be issued once the pre-check finds the branch"
fi
grep -qi 'feature' "$temporary_directory/existing.err" || fail "the failure must name the branch"

# --- --update path ----------------------------------------------------------
# The update must descend from the branch's current head, not from the base
# branch. The fake enforces that with the same ancestry rule GitHub applies to
# a `force:false` ref move, so a sibling commit fails here instead of only in
# production.
update_output="$(FAKE_HEAD_EXISTS=1 run_writer update o/r main feature "$manifest" "$message_file" --update)"
readonly update_log="$temporary_directory/update/log"
update_expected="$(cat <<'LOG'
GET repos/o/r/git/ref/heads/feature
GET repos/o/r/git/commits/headsha
POST repos/o/r/git/blobs
POST repos/o/r/git/blobs
POST repos/o/r/git/trees
POST repos/o/r/git/commits
PATCH repos/o/r/git/refs/heads/feature
LOG
)"
[[ "$(cat "$update_log")" == "$update_expected" ]] || {
  echo "--- actual ---" >&2; cat "$update_log" >&2
  fail "--update must read the existing head and never the base branch"
}
readonly update_calls="$temporary_directory/update/calls"
jq -e '.parents == ["headsha"] and .tree == "newtree"' "$update_calls/6.json" >/dev/null \
  || fail "--update must parent from the existing head: $(cat "$update_calls/6.json")"
jq -e '.base_tree == "headtree"' "$update_calls/5.json" >/dev/null \
  || fail "--update must build on the existing head's tree: $(cat "$update_calls/5.json")"
jq -e '.sha == "commitsha" and .force == false' "$update_calls/7.json" >/dev/null \
  || fail "--update must never force: $(cat "$update_calls/7.json")"
jq -e '.commit == "commitsha" and .files == 2' <<<"$update_output" >/dev/null || fail "update summary: $update_output"

# --- the fake's ancestry rule is real ---------------------------------------
# Proves the guard above can fail: a PATCH whose commit parents from the base
# instead of the current head is rejected, which is what the previous script
# produced on every repeat write.
readonly diverged_calls="$temporary_directory/diverged/calls"
readonly diverged_state="$temporary_directory/diverged/state"
mkdir -p "$diverged_calls" "$diverged_state"
: >"$temporary_directory/diverged/log"
jq -n '{parents:["base123"], tree:"newtree", message:"sibling"}' >"$temporary_directory/diverged-commit.json"
jq -n '{sha:"commitsha", force:false}' >"$temporary_directory/diverged-ref.json"
run_fake() {
  GH_LOG="$temporary_directory/diverged/log" GH_CALLS="$diverged_calls" \
    GH_STATE="$diverged_state" gh api --method "$1" "$2" --input "$3"
}
run_fake POST repos/o/r/git/commits "$temporary_directory/diverged-commit.json" >/dev/null
set +e
run_fake PATCH repos/o/r/git/refs/heads/feature "$temporary_directory/diverged-ref.json" \
  >/dev/null 2>"$temporary_directory/diverged.err"
diverged_status=$?
set -e
[[ "$diverged_status" -ne 0 ]] || fail "the fake must reject a non-fast-forward PATCH"
grep -q 'fast forward' "$temporary_directory/diverged.err" || fail "rejection must name the fast-forward rule"

# --- pre-check failure that is not a 404 must fail closed -------------------
set +e
FAKE_PRECHECK_STATUS=500 run_writer precheck o/r main feature "$manifest" "$message_file" \
  >/dev/null 2>"$temporary_directory/precheck.err"
precheck_status=$?
set -e
[[ "$precheck_status" -ne 0 ]] || fail "a non-404 pre-check failure must exit non-zero"
if grep -qE '^(POST|PATCH)' "$temporary_directory/precheck/log"; then
  echo "--- actual ---" >&2; cat "$temporary_directory/precheck/log" >&2
  fail "no Git object may be created when branch existence is unknown"
fi
grep -q 'could not determine' "$temporary_directory/precheck.err" \
  || fail "the failure must say existence could not be determined: $(cat "$temporary_directory/precheck.err")"

# --- authorship passthrough --------------------------------------------------
# Without the flags the commit carries no identity and GitHub attributes it to
# the authenticated account; with them, authorship is chosen by the caller.
jq -e 'has("author") == false and has("committer") == false' "$calls/7.json" >/dev/null \
  || fail "authorship must stay implicit when no identity is passed"

run_writer authored o/r main feature "$manifest" "$message_file" \
  --author 'A Name <a@example.invalid>' --committer 'B Name <b@example.invalid>' >/dev/null
readonly authored_commit="$temporary_directory/authored/calls/7.json"
jq -e '.author == {name:"A Name", email:"a@example.invalid"}
  and .committer == {name:"B Name", email:"b@example.invalid"}' "$authored_commit" >/dev/null \
  || fail "identity passthrough: $(cat "$authored_commit")"
jq -j '.message' "$authored_commit" | cmp -s - "$message_file" \
  || fail "an explicit identity must not alter the message"

set +e
run_writer malformed o/r main feature "$manifest" "$message_file" --author 'no-email' \
  >/dev/null 2>"$temporary_directory/malformed.err"
malformed_status=$?
set -e
[[ "$malformed_status" -eq 2 ]] || fail "a malformed identity must exit 2"
grep -q "Name <email>" "$temporary_directory/malformed.err" || fail "the identity failure must state the expected form"

# --- edge case: a manifest entry whose local file is missing ----------------
readonly bad_manifest="$temporary_directory/bad.json"
jq -n --arg a "$temporary_directory/absent.md" '[{path:"docs/a.md",file:$a}]' >"$bad_manifest"
set +e
run_writer missing o/r main feature "$bad_manifest" "$message_file" >/dev/null 2>"$temporary_directory/missing.err"
missing_status=$?
set -e
[[ "$missing_status" -ne 0 ]] || fail "a missing manifest file must fail"
grep -q 'absent.md' "$temporary_directory/missing.err" || fail "the failure must name the missing file"

# --- edge case: usage ------------------------------------------------------
set +e
"$writer" o/r main feature >/dev/null 2>&1
usage_status=$?
set -e
[[ "$usage_status" -eq 2 ]] || fail "missing arguments must exit 2"

echo "ok: tests/test_remote_write.sh"
