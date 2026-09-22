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
case "$endpoint" in
  */git/ref/heads/feature)
    [[ "${FAKE_HEAD_EXISTS:-0}" == 1 ]] || { echo "gh: Not Found" >&2; exit 1; }
    echo '{"object":{"sha":"headsha"}}' ;;
  */git/ref/heads/main) echo '{"object":{"sha":"base123"}}' ;;
  */git/commits/base123) echo '{"tree":{"sha":"tree123"}}' ;;
  */git/blobs) echo "{\"sha\":\"blob$call_index\"}" ;;
  */git/trees) echo '{"sha":"newtree"}' ;;
  */git/commits) echo '{"sha":"commitsha"}' ;;
  */git/refs|*/git/refs/heads/feature) echo '{"ref":"refs/heads/feature"}' ;;
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
  mkdir -p "$log_directory/calls"
  GH_LOG="$log_directory/log" GH_CALLS="$log_directory/calls" \
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
update_output="$(FAKE_HEAD_EXISTS=1 run_writer update o/r main feature "$manifest" "$message_file" --update)"
readonly update_log="$temporary_directory/update/log"
tail -n 1 "$update_log" | grep -qx 'PATCH repos/o/r/git/refs/heads/feature' \
  || fail "--update must PATCH the existing ref: $(cat "$update_log")"
update_calls="$(wc -l <"$update_log" | tr -d ' ')"
jq -e '.sha == "commitsha" and .force == false' "$temporary_directory/update/calls/$update_calls.json" >/dev/null \
  || fail "--update must never force: $(cat "$temporary_directory/update/calls/$update_calls.json")"
jq -e '.commit == "commitsha" and .files == 2' <<<"$update_output" >/dev/null || fail "update summary: $update_output"

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
