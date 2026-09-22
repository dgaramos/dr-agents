#!/usr/bin/env bash
set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly resolver="$repository_root/core/target-resolution/scripts/resolve-target.sh"
temporary_directory="$(mktemp -d)"
readonly temporary_directory="$(cd "$temporary_directory" && pwd -P)"
trap 'rm -rf "$temporary_directory"' EXIT

fail() { echo "not ok: $*" >&2; exit 1; }
assert_json() {
  local json="$1" label="$2"
  shift 2
  jq -e "$@" <<<"$json" >/dev/null || fail "$label: $json"
}
make_repository() {
  local directory="$1" remote="$2"
  mkdir -p "$directory"
  git -C "$directory" init -q
  git -C "$directory" remote add origin "$remote"
}

make_repository "$temporary_directory/cwd" "https://github.com/owner/A.git"
make_repository "$temporary_directory/roots/any-name" "git@github.com:owner/B.git"
make_repository "$temporary_directory/roots/B" "https://github.com/other/wrong.git"

pushd "$temporary_directory/cwd" >/dev/null
result="$(DR_AGENTS_REPO_ROOTS="$temporary_directory/roots" "$resolver" "https://github.com/owner/B/pull/7")"
assert_json "$result" "explicit PR and remote-based checkout" \
  --arg path "$temporary_directory/roots/any-name" --arg evidence "root-scan:$temporary_directory/roots" \
  '.target == "owner/B" and .host == "github.com" and .source == "explicit" and .reference == {kind:"pr",number:7} and .checkout == $path and .checkout_evidence == $evidence and .mode == "checkout"'

result="$(DR_AGENTS_REPO_ROOTS="$temporary_directory/none" "$resolver")"
assert_json "$result" "cwd origin precedence" --arg path "$temporary_directory/cwd" \
  '.target == "owner/A" and .source == "cwd" and .checkout == $path and .checkout_evidence == "cwd-origin"'
popd >/dev/null

references=(
  "https://github.com/o/r/pull/7"
  "https://github.com/o/r/issues/9"
  "o/r"
  "o/r#9"
  "git@github.com:o/r.git"
  "ssh://git@github.com/o/r"
)
for reference in "${references[@]}"; do
  result="$(cd "$temporary_directory" && DR_AGENTS_REPO_ROOTS="$temporary_directory/empty" "$resolver" "$reference" 2>/dev/null)"
  assert_json "$result" "normalize $reference" '.target == "o/r" and .host == "github.com" and .mode == "remote-only"'
done

result="$(cd "$temporary_directory" && "$resolver" --from-specs-repository Specs/Repo)"
assert_json "$result" "specs repository source" '.target == "Specs/Repo" and .source == "specs-repository"'

result="$(cd "$temporary_directory" && "$resolver" explicit/Target --from-specs-repository Specs/Repo)"
assert_json "$result" "explicit reference precedes specs repository" '.target == "explicit/Target" and .source == "explicit"'

for malformed in "o/r/extra" "https://github.com/o" ""; do
  stdout="$temporary_directory/stdout"
  stderr="$temporary_directory/stderr"
  set +e
  (cd "$temporary_directory" && "$resolver" "$malformed") >"$stdout" 2>"$stderr"
  status=$?
  set -e
  [[ "$status" -eq 2 && ! -s "$stdout" ]] || fail "malformed reference: '$malformed'"
done

set +e
(cd "$temporary_directory" && "$resolver") >"$temporary_directory/stdout" 2>"$temporary_directory/stderr"
status=$?
set -e
[[ "$status" -eq 4 && ! -s "$temporary_directory/stdout" ]] || fail "unknown cwd target"

make_repository "$temporary_directory/other" "https://github.com/owner/other.git"
make_repository "$temporary_directory/root-one/first" "https://github.com/owner/duplicate.git"
make_repository "$temporary_directory/root-two/second" "git@github.com:OWNER/DUPLICATE.git"
set +e
(cd "$temporary_directory/other" && DR_AGENTS_REPO_ROOTS="$temporary_directory/root-one:$temporary_directory/root-two" "$resolver" owner/duplicate) >"$temporary_directory/stdout" 2>"$temporary_directory/stderr"
status=$?
set -e
[[ "$status" -eq 3 && ! -s "$temporary_directory/stdout" ]] || fail "ambiguous checkout status"
grep -F "$temporary_directory/root-one/first" "$temporary_directory/stderr" >/dev/null || fail "first ambiguity candidate"
grep -F "$temporary_directory/root-two/second" "$temporary_directory/stderr" >/dev/null || fail "second ambiguity candidate"

result="$(cd "$temporary_directory/other" && DR_AGENTS_REPO_ROOTS="$temporary_directory/missing:$temporary_directory/roots" "$resolver" owner/B 2>"$temporary_directory/warning")"
grep -F "warning: repository root does not exist" "$temporary_directory/warning" >/dev/null || fail "missing root warning"
assert_json "$result" "continue after missing root" --arg path "$temporary_directory/roots/any-name" '.checkout == $path'

mkdir -p "$temporary_directory/path-without-gh"
ln -s "$(command -v git)" "$temporary_directory/path-without-gh/git"
ln -s "$(command -v jq)" "$temporary_directory/path-without-gh/jq"
ln -s "$(command -v dirname)" "$temporary_directory/path-without-gh/dirname"
ln -s "$(command -v find)" "$temporary_directory/path-without-gh/find"
ln -s "$(command -v sort)" "$temporary_directory/path-without-gh/sort"
ln -s "$(command -v tr)" "$temporary_directory/path-without-gh/tr"
result="$(cd "$temporary_directory/cwd" && PATH="$temporary_directory/path-without-gh:/bin" DR_AGENTS_REPO_ROOTS="$temporary_directory/empty" "$resolver")"
assert_json "$result" "resolver does not require gh" '.target == "owner/A"'

echo "ok: test_resolve_target.sh"
