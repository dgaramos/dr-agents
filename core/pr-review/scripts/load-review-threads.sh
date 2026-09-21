#!/usr/bin/env bash
# Load every review thread of a pull request with both identifiers a reviewer
# needs, in one portable, credential-free command.
#
# A reviewer needs two different identifiers per thread and they come from two
# different APIs: the GraphQL thread node id is what resolves a conversation,
# and the REST `databaseId` of a comment is what a reply targets. Producing them
# separately is how a publication ends up replying to the wrong thread, so this
# script is the single place they are produced together.
#
# Output (stdout, one JSON array):
#   [{thread_id, is_resolved, path, line, comments: [
#       {database_id, node_id, author, body, is_top_level, created_at}]}]
#
# `line` is null for an outdated thread; that is information, not an error.
# `is_top_level` is derived from `replyTo`, never from a comment's position.
#
# On any API failure the script exits 1 with nothing on stdout: a caller that
# pipes this into a manifest must not receive a half-read page set that looks
# like a complete one. Pages are therefore accumulated and printed only once the
# last page has been read.
#
# NOTE: this paging query is duplicated in validate-review-manifest.sh and
# verify-review-publication.sh, which are deliberately independent of this
# loader. dr-agents#322 owns consolidating the three into one query site.
set -euo pipefail

[[ $# == 2 ]] || {
  echo "usage: load-review-threads.sh OWNER/REPO PR_NUMBER" >&2
  exit 2
}
readonly repository="$1"
readonly pr_number="$2"
[[ "$repository" == */* ]] || { echo "repository must be OWNER/REPO" >&2; exit 2; }
[[ "$pr_number" =~ ^[1-9][0-9]*$ ]] || { echo "PR_NUMBER must be a positive integer" >&2; exit 2; }

readonly owner="${repository%%/*}"
readonly name="${repository##*/}"

readonly threads_query='
query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $after) {
        nodes {
          id
          isResolved
          path
          line
          comments(first: 100) {
            nodes { databaseId id author { login } body replyTo { id } createdAt }
            pageInfo { hasNextPage endCursor }
          }
        }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}'

# A thread with more than 100 comments needs its own cursor walk. Long threads
# are exactly the ones a duplicate-finding reply targets, so truncating them
# silently would defeat the purpose of the loader.
readonly comments_query='
query($thread: ID!, $after: String) {
  node(id: $thread) {
    ... on PullRequestReviewThread {
      comments(first: 100, after: $after) {
        nodes { databaseId id author { login } body replyTo { id } createdAt }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
}'

# Shape one GraphQL comment node into the documented output shape.
readonly comment_shape='{
  database_id: .databaseId,
  node_id: .id,
  author: (.author.login // null),
  body: .body,
  is_top_level: (.replyTo == null),
  created_at: .createdAt
}'

accumulator="$(mktemp)"
trap 'rm -f "$accumulator"' EXIT
: >"$accumulator"

# Walk the remaining comment pages of one thread, appending shaped comments.
load_remaining_comments() {
  local thread_id="$1" cursor="$2" dest="$3" page args
  while [[ -n "$cursor" && "$cursor" != null ]]; do
    args=(-f query="$comments_query" -f thread="$thread_id" -f after="$cursor")
    page="$(gh api graphql "${args[@]}")" || return 1
    jq -c ".data.node.comments.nodes[] | $comment_shape" <<<"$page" >>"$dest" || return 1
    if [[ "$(jq -r '.data.node.comments.pageInfo.hasNextPage' <<<"$page")" == true ]]; then
      cursor="$(jq -r '.data.node.comments.pageInfo.endCursor' <<<"$page")"
    else
      cursor=""
    fi
  done
}

cursor=""
while :; do
  args=(-f query="$threads_query" -f owner="$owner" -f name="$name" -F number="$pr_number")
  [[ -z "$cursor" ]] || args+=(-f after="$cursor")
  page="$(gh api graphql "${args[@]}")" || exit 1

  while IFS= read -r node; do
    [[ -n "$node" ]] || continue
    thread_id="$(jq -r '.id' <<<"$node")"
    comments_file="$(mktemp)"
    jq -c ".comments.nodes[] | $comment_shape" <<<"$node" >"$comments_file" || { rm -f "$comments_file"; exit 1; }
    if [[ "$(jq -r '.comments.pageInfo.hasNextPage' <<<"$node")" == true ]]; then
      load_remaining_comments "$thread_id" \
        "$(jq -r '.comments.pageInfo.endCursor' <<<"$node")" "$comments_file" \
        || { rm -f "$comments_file"; exit 1; }
    fi
    jq -c --slurpfile comments <(jq -s '.' "$comments_file") '{
      thread_id: .id,
      is_resolved: .isResolved,
      path: .path,
      line: .line,
      comments: $comments[0]
    }' <<<"$node" >>"$accumulator" || { rm -f "$comments_file"; exit 1; }
    rm -f "$comments_file"
  done < <(jq -c '.data.repository.pullRequest.reviewThreads.nodes[]' <<<"$page")

  [[ "$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage' <<<"$page")" == true ]] || break
  cursor="$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor' <<<"$page")"
done

# Only now, with every page read, is it safe to write to stdout.
jq -s '.' "$accumulator"
