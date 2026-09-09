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
if [[ "$*" == 'api user --jq .login' ]]; then echo example-user; exit 0; fi
case "$SCENARIO" in
  active) echo '{"workflows":[{"path":".github/workflows/publish-example.yml","state":"active"}]}' ;;
  absent) echo '{"workflows":[]}' ;;
  disabled) echo '{"workflows":[{"path":".github/workflows/publish-example.yml","state":"disabled_manually"}]}' ;;
  error) echo 'HTTP 403' >&2; exit 1 ;;
  malformed) echo '{}' ;;
esac
EOF
chmod +x "$temp/bin/gh"
export PATH="$temp/bin:$PATH" TEST_LOG="$temp/log"
for scenario in active absent disabled; do
  result="$(SCENARIO="$scenario" bash "$root/core/pr-review/scripts/select-publisher.sh" octo/example .github/workflows/publish-example.yml)"
  if [[ "$scenario" == active ]]; then
    jq -e '.route == "app"' <<<"$result" >/dev/null
    if grep -q 'api user' "$TEST_LOG"; then echo "active App must not select personal account" >&2; exit 1; fi
  else
    jq -e '.route == "personal" and .actor == "example-user" and (.reason | length > 0)' <<<"$result" >/dev/null
  fi
  rm "$TEST_LOG"
done
for scenario in error malformed; do
  if SCENARIO="$scenario" bash "$root/core/pr-review/scripts/select-publisher.sh" octo/example .github/workflows/publish-example.yml; then
    echo "unknown availability must not select fallback" >&2; exit 1
  fi
  if grep -q 'api user' "$TEST_LOG"; then echo "unknown availability queried fallback account" >&2; exit 1; fi
  rm "$TEST_LOG"
done
echo "publisher selection tests passed"
