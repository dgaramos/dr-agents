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
  echo "usage: remote-write.sh OWNER/REPO BASE_BRANCH NEW_BRANCH MANIFEST_PATH MESSAGE_FILE [--update] [--author 'Name <email>'] [--committer 'Name <email>']" >&2
  exit 2
}

# An identity is passed through to the git-data API verbatim. Authorship is
# therefore chosen by the caller instead of inherited from whichever account
# the `gh` session happens to authenticate; when neither flag is given, GitHub
# attributes the commit to that authenticated account as before. Identity is
# caller-supplied on purpose: this script is model-neutral and never names an
# adapter.
readonly identity_pattern='^[^<>]+ <[^<>[:space:]]+>$'
require_identity() {
  local role="$1" value="$2"
  [[ "$value" =~ $identity_pattern ]] || {
    echo "remote-write: --$role expects 'Name <email>', got '$value'" >&2
    exit 2
  }
}

update=false
author_identity=""
committer_identity=""
positional=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --update)
      [[ "$update" == false ]] || usage
      update=true
      shift
      ;;
    --author)
      [[ $# -ge 2 && -z "$author_identity" ]] || usage
      require_identity author "$2"
      author_identity="$2"
      shift 2
      ;;
    --committer)
      [[ $# -ge 2 && -z "$committer_identity" ]] || usage
      require_identity committer "$2"
      committer_identity="$2"
      shift 2
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
readonly author_identity
readonly committer_identity

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
# refuse --update against a branch that does not exist. The check fails closed:
# only a 404 proves absence, and any other failure (401, 403, rate limit, 5xx,
# network) stops before a single Git object is created rather than falling
# through to the create path.
precheck_body="$work_directory/precheck.json"
precheck_error="$work_directory/precheck.err"
head_sha=""
if api GET "repos/$repository/git/ref/heads/$new_branch" >"$precheck_body" 2>"$precheck_error"; then
  head_exists=true
  head_sha="$(jq -r '.object.sha // empty' "$precheck_body")"
  [[ -n "$head_sha" ]] || { echo "remote-write: branch '$new_branch' exists but reports no sha" >&2; exit 1; }
elif grep -q 'HTTP 404' "$precheck_error"; then
  head_exists=false
else
  echo "remote-write: could not determine whether branch '$new_branch' exists in $repository; refusing to write" >&2
  sed 's/^/remote-write: gh: /' "$precheck_error" >&2
  exit 1
fi
readonly head_exists head_sha
if [[ "$head_exists" == true && "$update" == false ]]; then
  echo "remote-write: branch '$new_branch' already exists in $repository; pass --update to move it" >&2
  exit 1
fi
if [[ "$head_exists" == false && "$update" == true ]]; then
  echo "remote-write: branch '$new_branch' does not exist in $repository; omit --update to create it" >&2
  exit 1
fi

# The parent is the commit the write must descend from: the existing branch
# head under --update, the base branch when creating. Parenting an update from
# the base commit would make the new commit a sibling of the current head, and
# GitHub would reject the `force: false` ref move as non-fast-forward.
if [[ "$update" == true ]]; then
  parent_sha="$head_sha"
else
  parent_sha="$(api GET "repos/$repository/git/ref/heads/$base_branch" | jq -r '.object.sha')"
  [[ -n "$parent_sha" && "$parent_sha" != null ]] || { echo "remote-write: base branch '$base_branch' has no sha" >&2; exit 1; }
fi
readonly parent_sha
base_tree="$(api GET "repos/$repository/git/commits/$parent_sha" | jq -r '.tree.sha')"
[[ -n "$base_tree" && "$base_tree" != null ]] || { echo "remote-write: parent commit $parent_sha has no tree" >&2; exit 1; }

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

identity_request="$work_directory/identity.json"
echo '{}' >"$identity_request"
for pair in "author:$author_identity" "committer:$committer_identity"; do
  role="${pair%%:*}"
  identity="${pair#*:}"
  [[ -n "$identity" ]] || continue
  name="${identity%% <*}"
  email="${identity##*<}"
  email="${email%>}"
  jq --arg role "$role" --arg name "$name" --arg email "$email" \
    '. + {($role): {name:$name, email:$email}}' "$identity_request" >"$identity_request.next"
  mv "$identity_request.next" "$identity_request"
done

commit_request="$work_directory/commit.json"
jq -n --rawfile message "$message_file" --arg tree "$tree_sha" --arg parent "$parent_sha" \
  --slurpfile identity "$identity_request" \
  '{message:$message, tree:$tree, parents:[$parent]} + $identity[0]' >"$commit_request"
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
