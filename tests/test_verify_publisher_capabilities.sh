#!/usr/bin/env bash
# The capability gate must read the App token's actual inputs.
#
# dr-agents#449 review: the first version searched the whole YAML file with a
# fixed-string grep, so the required permission could be satisfied by the same
# words in a comment while the token no longer requested it -- the exact 403
# the gate exists to prevent could regress with the gate green.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${CAPABILITY_SCRIPT:-$root/.github/scripts/verify-publisher-capabilities.sh}"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# Build a case directory holding one reusable publisher definition.
make_case() {
  local name="$1" body="$2"
  mkdir -p "$temp/$name"
  printf '%s\n' "$body" >"$temp/$name/reusable-publish-probe.yml"
}

run_case() {
  local name="$1"
  set +e
  CASE_STDERR="$(bash "$script" "$temp/$name" 2>&1 >/dev/null)"
  CASE_STATUS=$?
  set -e
}

token_step() {
  cat <<'YAML'
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - name: Mint the App token
        id: app
        uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1
        with:
          client-id: ${{ inputs.client_id }}
          private-key: ${{ secrets.app_private_key }}
YAML
}

# --- Happy path: both permissions are real inputs. ---------------------------
make_case granted "# publisher-targets: issues pull-requests
$(token_step)
          permission-issues: write
          permission-pull-requests: write
      - name: Publish
        run: true"
run_case granted
[[ "$CASE_STATUS" == 0 ]] ||
  fail "granted: both permissions are real inputs but the verifier exited $CASE_STATUS: $CASE_STDERR"

# --- The regression this test exists for: permission text in a comment. ------
make_case commented "# publisher-targets: issues pull-requests
# permission-pull-requests: write
$(token_step)
          permission-issues: write
          # permission-pull-requests: write
      - name: Publish
        run: true"
run_case commented
[[ "$CASE_STATUS" == 1 ]] || fail \
  "commented: the pull-requests permission appears only in comments, but the" \
  "verifier exited $CASE_STATUS; the gate is matching arbitrary file text"
[[ "$CASE_STDERR" == *"permission-pull-requests: write"* ]] ||
  fail "commented: stderr must name the missing permission, got: $CASE_STDERR"

# --- Permission text in an unrelated step must not count either. -------------
make_case elsewhere "# publisher-targets: issues pull-requests
$(token_step)
          permission-issues: write
      - name: Unrelated step
        env:
          NOTE: 'permission-pull-requests: write'
        run: echo 'permission-pull-requests: write'"
run_case elsewhere
[[ "$CASE_STATUS" == 1 ]] || fail \
  "elsewhere: the permission text lives in an unrelated step, but the verifier" \
  "exited $CASE_STATUS"

# --- A declared target with no token step at all. ----------------------------
make_case tokenless "# publisher-targets: issues
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - name: Publish
        run: true"
run_case tokenless
[[ "$CASE_STATUS" == 1 ]] ||
  fail "tokenless: a definition with no App-token step must fail, got $CASE_STATUS"
[[ "$CASE_STDERR" == *"create-github-app-token"* ]] ||
  fail "tokenless: stderr must name the missing step, got: $CASE_STDERR"

# --- A publisher with no marker fails for lacking one. -----------------------
make_case unmarked "$(token_step)
          permission-issues: write"
run_case unmarked
[[ "$CASE_STATUS" == 1 ]] ||
  fail "unmarked: a definition with no marker must fail, got $CASE_STATUS"
[[ "$CASE_STDERR" == *"publisher-targets"* ]] ||
  fail "unmarked: stderr must name the missing marker, got: $CASE_STDERR"

# --- An unknown target type is a typo, not a pass. ---------------------------
make_case unknown "# publisher-targets: discussions
$(token_step)
          permission-issues: write"
run_case unknown
[[ "$CASE_STATUS" == 1 ]] ||
  fail "unknown: an unrecognised target must fail, got $CASE_STATUS"
[[ "$CASE_STDERR" == *"discussions"* ]] ||
  fail "unknown: stderr must name the target, got: $CASE_STDERR"

# --- The repository's own publishers must satisfy the gate. ------------------
bash "$script" "$root/.github/workflows" ||
  fail "catalog: the repository's own publisher definitions fail the capability gate"

echo "PASS: $(basename "${BASH_SOURCE[0]}")"
