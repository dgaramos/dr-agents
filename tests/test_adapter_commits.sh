#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
git init -q "$temp/repo"
cd "$temp/repo"
git config user.name Tester
git config user.email tester@example.test
git config commit.gpgsign false
for adapter in cody claudio; do
  case "$adapter" in cody) bot_id=318732897 ;; claudio) bot_id=318764128 ;; esac
  cat >"$temp/message" <<'EOF'
fix: verify attribution

Co-authored-by: Claude <noreply@anthropic.com>
Co-Authored-By: Codex <codex@openai.com>
Co-Authored-By: cody-dr[bot] <cody-dr[bot]@users.noreply.github.com>
Co-Authored-By: claudio-dr[bot] <claudio-dr[bot]@users.noreply.github.com>
Co-Authored-By: Human <human@example.test>
EOF
  bash "$root/plugins/${adapter}-dr/scripts/commit.sh" "$temp/message" --allow-empty
  git log -1 --format=%B >"$temp/actual"
  grep -Fx "Co-Authored-By: ${adapter}-dr[bot] <${bot_id}+${adapter}-dr[bot]@users.noreply.github.com>" "$temp/actual"
  grep -Fx 'Co-Authored-By: Human <human@example.test>' "$temp/actual"
  [[ "$(git log -1 --format=%ae)" == tester@example.test ]]
  [[ "$(git log -1 --format=%B | git interpret-trailers --parse | wc -l | tr -d ' ')" == 2 ]]
done
if bash "$root/plugins/cody-dr/scripts/commit.sh" "$temp/missing" --allow-empty; then
  echo "missing message must fail" >&2
  exit 1
fi
echo "adapter commit tests passed"
