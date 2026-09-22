#!/usr/bin/env bash
set -euo pipefail

# Create or update a branch in a target repository through the git-data API,
# without a local checkout. Uses the authenticated `gh` session only; it never
# reads, stores or accepts a token, and it never creates a pull request.
#
# Content and commit messages are passed to `gh api --input` as JSON built by
# `jq`, so no file byte or message character is ever interpolated into a shell
# word.

usage() {
  echo "usage: remote-write.sh OWNER/REPO BASE_BRANCH NEW_BRANCH MANIFEST_PATH MESSAGE_FILE [--update]" >&2
  exit 2
}

update=false
positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --update)
      [[ "$update" == false ]] || usage
      update=true
      shift
      ;;
    --*) usage ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done
[[ "${#positional[@]}" -eq 5 ]] || usage

readonly repository="${positional[0]}"
readonly base_branch="${positional[1]}"
readonly new_branch="${positional[2]}"
readonly manifest_path="${positional[3]}"
readonly message_file="${positional[4]}"
readonly update

[[ "$repository" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
  echo "remote-write: OWNER/REPO expected, got '$repository'" >&2
  exit 2
}
for required in "$manifest_path" "$message_file"; do
  [[ -f "$required" ]] || { echo "remote-write: no such file: $required" >&2; exit 2; }
done
jq -e 'type == "array" and length > 0 and all(.path? != null and .file? != null)' "$manifest_path" >/dev/null 2>&1 || {
  echo "remote-write: manifest must be a non-empty array of {\"path\",\"file\"} entries: $manifest_path" >&2
  exit 2
}

work_directory="$(mktemp -d)"
readonly work_directory
created_blobs=()
created_commit=""
report_partial_state() {
  local status=$?
  if [[ $status -ne 0 ]]; then
    if [[ "${#created_blobs[@]}" -gt 0 ]]; then
      echo "remote-write: created blobs: ${created_blobs[*]}" >&2
    fi
    if [[ -n "$created_commit" ]]; then
      echo "remote-write: created commit: $created_commit" >&2
    fi
  fi
  rm -rf "$work_directory"
}
trap report_partial_state EXIT

api() {
  # api METHOD ENDPOINT [INPUT_FILE]
  local method="$1" endpoint="$2" input="${3:-}"
  if [[ -n "$input" ]]; then
    gh api --method "$method" "$endpoint" --input "$input"
  else
    gh api --method "$method" "$endpoint"
  fi
}

# Pre-check before any write: refuse an existing branch unless --update, and
# refuse --update against a branch that does not exist.
head_exists=true
api GET "repos/$repository/git/ref/heads/$new_branch" >/dev/null 2>&1 || head_exists=false
if [[ "$head_exists" == true && "$update" == false ]]; then
  echo "remote-write: branch '$new_branch' already exists in $repository; pass --update to move it" >&2
  exit 1
fi
if [[ "$head_exists" == false && "$update" == true ]]; then
  echo "remote-write: branch '$new_branch' does not exist in $repository; omit --update to create it" >&2
  exit 1
fi

base_sha="$(api GET "repos/$repository/git/ref/heads/$base_branch" | jq -r '.object.sha')"
[[ -n "$base_sha" && "$base_sha" != null ]] || { echo "remote-write: base branch '$base_branch' has no sha" >&2; exit 1; }
base_tree="$(api GET "repos/$repository/git/commits/$base_sha" | jq -r '.tree.sha')"
[[ -n "$base_tree" && "$base_tree" != null ]] || { echo "remote-write: base commit $base_sha has no tree" >&2; exit 1; }

entry_count="$(jq 'length' "$manifest_path")"
tree_entries="$work_directory/tree-entries.json"
echo '[]' >"$tree_entries"

for index in $(seq 0 $((entry_count - 1))); do
  entry_path="$(jq -r ".[$index].path" "$manifest_path")"
  entry_file="$(jq -r ".[$index].file" "$manifest_path")"
  [[ -f "$entry_file" ]] || { echo "remote-write: no such file for '$entry_path': $entry_file" >&2; exit 1; }

  blob_request="$work_directory/blob-$index.json"
  base64 <"$entry_file" | tr -d '\n' >"$work_directory/blob-$index.b64"
  jq -n --rawfile content "$work_directory/blob-$index.b64" \
    '{content:($content | rtrimstr("\n")), encoding:"base64"}' >"$blob_request"

  blob_sha="$(api POST "repos/$repository/git/blobs" "$blob_request" | jq -r '.sha')"
  [[ -n "$blob_sha" && "$blob_sha" != null ]] || { echo "remote-write: blob upload for '$entry_path' returned no sha" >&2; exit 1; }
  created_blobs+=("$blob_sha")

  jq --arg path "$entry_path" --arg sha "$blob_sha" \
    '. + [{path:$path, mode:"100644", type:"blob", sha:$sha}]' "$tree_entries" >"$tree_entries.next"
  mv "$tree_entries.next" "$tree_entries"
done

tree_request="$work_directory/tree.json"
jq --arg base_tree "$base_tree" '{base_tree:$base_tree, tree:.}' "$tree_entries" >"$tree_request"
tree_sha="$(api POST "repos/$repository/git/trees" "$tree_request" | jq -r '.sha')"
[[ -n "$tree_sha" && "$tree_sha" != null ]] || { echo "remote-write: tree creation returned no sha" >&2; exit 1; }

commit_request="$work_directory/commit.json"
jq -n --rawfile message "$message_file" --arg tree "$tree_sha" --arg parent "$base_sha" \
  '{message:$message, tree:$tree, parents:[$parent]}' >"$commit_request"
commit_sha="$(api POST "repos/$repository/git/commits" "$commit_request" | jq -r '.sha')"
[[ -n "$commit_sha" && "$commit_sha" != null ]] || { echo "remote-write: commit creation returned no sha" >&2; exit 1; }
created_commit="$commit_sha"

ref_request="$work_directory/ref.json"
if [[ "$update" == true ]]; then
  jq -n --arg sha "$commit_sha" '{sha:$sha, force:false}' >"$ref_request"
  api PATCH "repos/$repository/git/refs/heads/$new_branch" "$ref_request" >/dev/null
else
  jq -n --arg ref "refs/heads/$new_branch" --arg sha "$commit_sha" '{ref:$ref, sha:$sha}' >"$ref_request"
  api POST "repos/$repository/git/refs" "$ref_request" >/dev/null
fi

jq -n --arg commit "$commit_sha" --arg ref "refs/heads/$new_branch" --argjson files "$entry_count" \
  '{commit:$commit, ref:$ref, files:$files}'
