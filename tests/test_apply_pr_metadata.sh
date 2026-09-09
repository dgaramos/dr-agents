#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
mkdir -p "$temp/bin"
log="$temp/gh.log"

cat >"$temp/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$TEST_GH_LOG"
case "$1 $2" in
  "api --paginate") echo '[{"number":1,"title":"v1"}]' ;;
  "api repos/octo/example/milestones/1") echo v1 ;;
  "project view") echo '{"id":"PVT_test","title":"Example project"}' ;;
  "project item-add") echo '{"id":"PVTI_test"}' ;;
  "project field-list") echo '{"fields":[{"id":"PVTSSF_status","name":"Status","options":[{"id":"todo","name":"Todo"},{"id":"progress","name":"In Progress"}]}]}' ;;
  "project item-list") echo '{"items":[{"id":"PVTI_test","status":"In Progress"}]}' ;;
  "project item-edit") ;;
  "api repos/octo/example/pulls/12") echo '{"base":{"ref":"main"},"labels":[{"name":"enhancement"},{"name":"core"}],"milestone":{"title":"v1"},"assignees":[{"login":"octo"}],"requested_reviewers":[{"login":"reviewer"}],"requested_teams":[]}' ;;
  "api --method") cat >>"$TEST_GH_LOG" ;;
  *) echo "unexpected gh operation: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$temp/bin/gh"

TEST_GH_LOG="$log" PATH="$temp/bin:$PATH" "$root/core/issue-workflow/scripts/apply-pr-metadata.sh" \
  --repo octo/example --pr 12 --base main --label enhancement --label core --milestone v1 \
  --assignee octo --reviewer reviewer --project-owner octo --project-number 7 --project-status 'In Progress'

grep -q -- 'api --method POST repos/octo/example/issues/12/labels --input -' "$log"
grep -q -- 'api --method PATCH repos/octo/example/issues/12 --input -' "$log"
grep -q -- 'project item-edit --id PVTI_test --project-id PVT_test --field-id PVTSSF_status --single-select-option-id progress' "$log"
grep -q -- 'project item-list 7 --owner octo --limit 1000 --format json' "$log"
rm "$log"
TEST_GH_LOG="$log" PATH="$temp/bin:$PATH" "$root/core/issue-workflow/scripts/apply-pr-metadata.sh" \
  --repo octo/example --pr 12 --base main --label enhancement --milestone 1
if grep -Eq 'project|pr edit|pr view|graphql' "$log"; then
  echo "ordinary metadata must not query Projects or use gh pr edit" >&2
  exit 1
fi
if TEST_GH_LOG="$log" PATH="$temp/bin:$PATH" "$root/core/issue-workflow/scripts/apply-pr-metadata.sh" \
  --repo octo/example --pr 12 --base wrong --label enhancement; then
  echo "expected wrong base to fail" >&2
  exit 1
fi
echo "apply-pr-metadata tests passed"
