#!/usr/bin/env bash
set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT

mkdir -p "$temporary_directory/bin"
cat > "$temporary_directory/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$GH_CALL_LOG"
case "$*" in
  *addPullRequestReviewThreadReply*)
    printf '%s\n' '{"data":{"addPullRequestReviewThreadReply":{"comment":{"author":{"login":"'"${REPLY_AUTHOR_LOGIN:-claudio-dr[bot]}"'"},"pullRequest":{"number":12,"repository":{"nameWithOwner":"octo/example"}}}}}}'
    ;;
  *resolveReviewThread*)
    printf '%s\n' true
    ;;
  *)
    printf '%s\n' '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"id":"thread-one"}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}'
    ;;
esac
EOF
chmod +x "$temporary_directory/bin/gh"

run_action() {
  env \
    GH_TOKEN=test-token \
    GITHUB_REPOSITORY=octo/example \
    PR_NUMBER=12 \
    THREAD_ID=thread-one \
    EXPECTED_AUTHOR='claudio-dr[bot]' \
    PUBLISHER_APP_SLUG=claudio-dr \
    GH_CALL_LOG="$temporary_directory/gh.log" \
    PATH="$temporary_directory/bin:$PATH" \
    "$@" \
    bash "$repository_root/.github/scripts/publish-claudio-thread-action.sh"
}

run_action THREAD_ACTION=reply BODY='Thanks, fixed.'
grep -qF 'addPullRequestReviewThreadReply' "$temporary_directory/gh.log"

run_action THREAD_ACTION=resolve
grep -qF 'resolveReviewThread' "$temporary_directory/gh.log"

if run_action THREAD_ACTION=reply THREAD_ID=thread-mismatch BODY='Must not post.'; then
  echo "reply unexpectedly accepted a thread outside the target PR" >&2
  exit 1
fi
! tail -n 1 "$temporary_directory/gh.log" | grep -qF 'addPullRequestReviewThreadReply'

run_action THREAD_ACTION=reply BODY='Unsuffixed login.' REPLY_AUTHOR_LOGIN='claudio-dr'
tail -n 1 "$temporary_directory/gh.log" | grep -qF 'addPullRequestReviewThreadReply'

run_action THREAD_ACTION=reply BODY='Suffixed login.' REPLY_AUTHOR_LOGIN='claudio-dr[bot]'
tail -n 1 "$temporary_directory/gh.log" | grep -qF 'addPullRequestReviewThreadReply'

if run_action THREAD_ACTION=reply BODY='Must not verify.' REPLY_AUTHOR_LOGIN='attacker'; then
  echo "reply verification accepted an author that is not the expected app" >&2
  exit 1
fi

diff "$repository_root/.github/scripts/publish-claudio-thread-action.sh" \
  "$repository_root/.github/scripts/publish-cody-thread-action.sh" >/dev/null || {
  echo "claudio and cody thread action scripts are no longer byte-identical" >&2
  exit 1
}

echo "claudio thread action tests passed"
