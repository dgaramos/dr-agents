#!/usr/bin/env bash
# Discovery of the permanent smoke target issue, by label and author.
#
# The first real run of the smoke test failed here, and the defect was the same
# class as dr-agents#258: one login form compared against another. There it was
# `claudio-dr` against `claudio-dr[bot]`; here it was `claudio-dr` against
# `app/claudio-dr`, which is what `gh issue list --json author` returns for an
# App. The comparison never matched, so every run created a fresh target and the
# permanent-issue design produced exactly the litter it existed to prevent.
#
# The fix normalizes BOTH sides rather than swapping one literal for another,
# because the surfaces genuinely disagree and a third form would otherwise
# reintroduce the bug:
#
#   gh issue list --json author   ->  app/claudio-dr
#   REST .user.login              ->  claudio-dr[bot]
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
mkdir -p "$temp/bin"

# Real `gh` evaluates --jq itself, so the stub has to as well: the filter is
# the thing under test here.
cat >"$temp/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >>"$TEST_LOG"
filter='.'
prev=""
for arg in "$@"; do
  [[ "$prev" == "--jq" ]] && filter="$arg"
  prev="$arg"
done
jq -r "$filter" "$ISSUES"
EOF
chmod +x "$temp/bin/gh"
export PATH="$temp/bin:$PATH"
export TEST_LOG="$temp/log" ISSUES="$temp/issues"
export GH_TOKEN=stub GITHUB_REPOSITORY=octo/example

readonly script="$root/.github/scripts/smoke-find-issue-target.sh"
failures=0

check() {
  local label="$1" expected="$2" agent="$3"
  local actual
  actual="$(AGENT="$agent" bash "$script" 2>"$temp/err" || true)"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL ${label}: expected '${expected}', got '${actual}'" >&2
    cat "$temp/err" >&2
    failures=$((failures + 1))
    return
  fi
  echo "ok ${label}"
}

# The form that actually broke production.
cat >"$ISSUES" <<'EOF'
[{"number":271,"author":{"login":"app/claudio-dr"}},
 {"number":272,"author":{"login":"app/cody-dr"}}]
EOF
check "app/ prefix is matched" 271 claudio
check "app/ prefix, other agent" 272 cody

# The REST form, in case the surface ever changes under us.
cat >"$ISSUES" <<'EOF'
[{"number":31,"author":{"login":"claudio-dr[bot]"}},
 {"number":32,"author":{"login":"cody-dr[bot]"}}]
EOF
check "[bot] suffix is matched" 31 claudio
check "[bot] suffix, other agent" 32 cody

# The bare form.
cat >"$ISSUES" <<'EOF'
[{"number":41,"author":{"login":"claudio-dr"}}]
EOF
check "bare login is matched" 41 claudio

# Both decorations at once.
cat >"$ISSUES" <<'EOF'
[{"number":51,"author":{"login":"app/claudio-dr[bot]"}}]
EOF
check "prefix and suffix together" 51 claudio

# A near-miss must not match: a human whose name merely contains the agent's.
cat >"$ISSUES" <<'EOF'
[{"number":61,"author":{"login":"not-claudio-dr"}},
 {"number":62,"author":{"login":"claudio-dr-testing"}}]
EOF
check "near-miss logins are rejected" "" claudio

# Nothing yet: empty output, exit 0. The caller passes the empty string to the
# issue publisher, which then takes its creation path. An error here would
# reinstate the manual bootstrap this replaced.
echo '[]' >"$ISSUES"
check "no target yet yields empty" "" claudio
if ! AGENT=claudio bash "$script" >/dev/null 2>&1; then
  echo "FAIL: an absent target must not be an error" >&2
  failures=$((failures + 1))
fi

# The oldest target wins, so two runs racing cannot settle on different issues.
cat >"$ISSUES" <<'EOF'
[{"number":273,"author":{"login":"app/claudio-dr"}},
 {"number":271,"author":{"login":"app/claudio-dr"}}]
EOF
check "the lowest number wins when duplicates exist" 271 claudio

# The repository must be named explicitly: these jobs run without a checkout,
# so gh cannot infer it from a git remote. This is the other half of the same
# failed run.
cat >"$ISSUES" <<'EOF'
[{"number":271,"author":{"login":"app/claudio-dr"}}]
EOF
: >"$TEST_LOG"
AGENT=claudio bash "$script" >/dev/null
if ! grep -q -- "--repo octo/example" "$TEST_LOG"; then
  echo "FAIL: discovery must name the repository explicitly (no checkout to infer it from)" >&2
  cat "$TEST_LOG" >&2
  failures=$((failures + 1))
else
  echo "ok repository named explicitly"
fi

if (( failures > 0 )); then
  echo "${failures} discovery assertion(s) failed" >&2
  exit 1
fi
echo "smoke issue target discovery tests passed"
