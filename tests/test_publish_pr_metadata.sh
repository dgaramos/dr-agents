#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
mkdir -p "$temp/bin" "$temp/core/issue-workflow/scripts"
log="$temp/log"

cat >"$temp/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$TEST_LOG"
EOF
chmod +x "$temp/bin/gh"
cat >"$temp/core/issue-workflow/scripts/apply-pr-metadata.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_LOG"
EOF
chmod +x "$temp/core/issue-workflow/scripts/apply-pr-metadata.sh"

cd "$temp"
TEST_LOG="$log" PATH="$temp/bin:$PATH" GITHUB_REPOSITORY=octo/example \
  PR_NUMBER=12 BASE_BRANCH=main LABELS_JSON='["enhancement","core"]' \
  ASSIGNEES_JSON='["octo"]' MILESTONE_NUMBER=3 PROJECT_OWNER=octo \
  PROJECT_GH_TOKEN=test-project-token PROJECT_NUMBER=7 PROJECT_STATUS='In Progress' EXPECTED_AUTHOR='cody-dr[bot]' \
  PUBLISHER_APP_SLUG=cody-dr \
  bash "$root/.github/scripts/publish-pr-metadata.sh"

if TEST_LOG="$log" PATH="$temp/bin:$PATH" GITHUB_REPOSITORY=octo/example \
  PR_NUMBER=12 BASE_BRANCH=main EXPECTED_AUTHOR='cody-dr[bot]' \
  PUBLISHER_APP_SLUG=unexpected-app \
  bash "$root/.github/scripts/publish-pr-metadata.sh" 2>/dev/null; then
  echo "expected mismatched app slug to fail" >&2
  exit 1
fi

if grep -q -- 'api user' "$log"; then
  echo "metadata publishing must not query the user endpoint" >&2
  exit 1
fi
# Core metadata and Project V2 are now separate calls so that a Project failure
# does not prevent labels/milestone/assignee from being applied.
grep -q -- '--repo octo/example --pr 12 --base main --label enhancement --label core --assignee octo --milestone 3' "$log"
grep -q -- '--repo octo/example --pr 12 --base main --project-owner octo --project-number 7 --project-status In Progress' "$log"

# Verify that a failing Project V2 step does NOT cause the script to exit non-zero.
rm -f "$log"
TEST_LOG="$log" PATH="$temp/bin:$PATH" GITHUB_REPOSITORY=octo/example \
  PR_NUMBER=12 BASE_BRANCH=main PROJECT_OWNER=octo PROJECT_NUMBER=7 \
  PROJECT_STATUS=Todo EXPECTED_AUTHOR='cody-dr[bot]' PUBLISHER_APP_SLUG=cody-dr \
  bash "$root/.github/scripts/publish-pr-metadata.sh" 2>"$temp/warnings"
grep -q 'Project pending' "$temp/warnings"
if grep -q -- '--project-owner' "$log"; then
  echo "Project calls must be skipped without a Project token" >&2
  exit 1
fi

rm -f "$log"
cat >"$temp/core/issue-workflow/scripts/apply-pr-metadata.sh" <<'EOF'
#!/usr/bin/env bash
if printf '%s\n' "$*" | grep -q -- '--project-owner'; then
  printf '%s\n' "$*" >>"$TEST_LOG"
  exit 1
fi
printf '%s\n' "$*" >>"$TEST_LOG"
EOF
chmod +x "$temp/core/issue-workflow/scripts/apply-pr-metadata.sh"

if ! TEST_LOG="$log" PATH="$temp/bin:$PATH" GITHUB_REPOSITORY=octo/example \
  PR_NUMBER=12 BASE_BRANCH=main LABELS_JSON='["enhancement"]' \
  ASSIGNEES_JSON='["octo"]' MILESTONE_NUMBER=3 PROJECT_OWNER=octo \
  PROJECT_GH_TOKEN=test-project-token PROJECT_NUMBER=7 PROJECT_STATUS='In Progress' EXPECTED_AUTHOR='cody-dr[bot]' \
  PUBLISHER_APP_SLUG=cody-dr \
  bash "$root/.github/scripts/publish-pr-metadata.sh" 2>/dev/null; then
  echo "a failing Project V2 step must not abort the script" >&2
  exit 1
fi
grep -q -- '--repo octo/example --pr 12 --base main --label enhancement --assignee octo --milestone 3' "$log"

cat >"$temp/core/issue-workflow/scripts/apply-pr-metadata.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
if TEST_LOG="$log" PATH="$temp/bin:$PATH" GITHUB_REPOSITORY=octo/example \
  PR_NUMBER=12 BASE_BRANCH=main EXPECTED_AUTHOR='cody-dr[bot]' \
  PUBLISHER_APP_SLUG=cody-dr bash "$root/.github/scripts/publish-pr-metadata.sh"; then
  echo "core metadata failure must fail the workflow" >&2
  exit 1
fi
echo "publish-pr-metadata tests passed"
