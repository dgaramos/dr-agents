#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
mkdir -p "$temp/bin"
cat >"$temp/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >>"$TEST_LOG"
case "$*" in
  'api --method GET '*)
    if [[ "${EXISTING:-false}" == true ]]; then jq -s '.' "$RESULT"; else echo '[]'; fi ;;
  'api --method POST '*) cat >"$PAYLOAD"; cat "$RESULT" ;;
  'api repos/octo/example/pulls/12') cat "$RESULT" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$temp/bin/gh"
export PATH="$temp/bin:$PATH" TEST_LOG="$temp/log" RESULT="$temp/result" PAYLOAD="$temp/payload"
export GITHUB_REPOSITORY=octo/example TITLE='fix: publisher' BODY='Body with `literal` text' HEAD_BRANCH=fix/publisher BASE_BRANCH=main
for adapter in cody claudio; do
  export EXPECTED_AUTHOR="${adapter}-dr[bot]" PUBLISHER_APP_SLUG="${adapter}-dr"
  jq -n --arg actor "$EXPECTED_AUTHOR" --arg title "$TITLE" --arg body "$BODY" \
    '{number:12,user:{login:$actor},title:$title,body:$body,head:{ref:"fix/publisher",repo:{full_name:"octo/example"}},base:{ref:"main",repo:{full_name:"octo/example"}},html_url:"https://github.com/octo/example/pull/12"}' >"$RESULT"
  bash "$root/.github/scripts/publish-pr.sh"
  jq -e --arg body "$BODY" '.body == $body and .head == "fix/publisher" and .base == "main"' "$PAYLOAD" >/dev/null
  rm "$TEST_LOG"
  EXISTING=true bash "$root/.github/scripts/publish-pr.sh"
  if grep -q POST "$TEST_LOG"; then echo "retry created a duplicate PR" >&2; exit 1; fi
done
if PUBLISHER_APP_SLUG=wrong bash "$root/.github/scripts/publish-pr.sh"; then
  echo "wrong authenticated app must fail" >&2; exit 1
fi
jq '.user.login = "someone-else"' "$RESULT" >"$temp/wrong"
if RESULT="$temp/wrong" EXISTING=true bash "$root/.github/scripts/publish-pr.sh"; then
  echo "wrong existing author must fail" >&2; exit 1
fi
echo "publish PR tests passed"
