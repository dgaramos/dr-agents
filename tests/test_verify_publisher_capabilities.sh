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
        env:
          GH_TOKEN: \${{ steps.app.outputs.token }}
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
        env:
          GH_TOKEN: \${{ steps.app.outputs.token }}
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
        env:
          GH_TOKEN: \${{ steps.app.outputs.token }}
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


# --- dr-agents#449 re-review: a permission on an UNRELATED App-token step must
# --- not satisfy a target. A definition may mint more than one token for
# --- different purposes -- reusable-publish-pr-metadata.yml mints a second,
# --- Projects-scoped one -- and unioning them let a write permission the
# --- publishing token does not hold make the gate pass. The same 403, one
# --- indirection further out.
make_case unrelated_token "# publisher-targets: issues pull-requests
$(token_step)
          permission-issues: write
      - name: Mint an unrelated token
        id: other
        uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1
        with:
          client-id: \${{ inputs.client_id }}
          private-key: \${{ secrets.app_private_key }}
          permission-pull-requests: write
      - name: Publish
        env:
          GH_TOKEN: \${{ steps.app.outputs.token }}
        run: true"
run_case unrelated_token
[[ "$CASE_STATUS" == 1 ]] ||
  fail "unrelated_token: a permission on a non-publishing token satisfied the gate (exit $CASE_STATUS)"
grep -qF "step 'app'" <<<"$CASE_STDERR" ||
  fail "unrelated_token: the failure must name the publishing token step; got: $CASE_STDERR"

# --- A definition that binds no GH_TOKEN has no publishing token to validate,
# --- which is a failure rather than something to skip quietly.
make_case unbound "# publisher-targets: issues
$(token_step)
          permission-issues: write
      - name: Publish
        run: true"
run_case unbound
[[ "$CASE_STATUS" == 1 ]] ||
  fail "unbound: a definition binding no GH_TOKEN was accepted (exit $CASE_STATUS)"
grep -qF "binds no GH_TOKEN" <<<"$CASE_STDERR" ||
  fail "unbound: the failure must say the definition binds no GH_TOKEN; got: $CASE_STDERR"


# --- dr-agents#449 re-review 2: a comment naming a different, privileged token
# --- must not redirect validation away from the token the publishing step
# --- consumes. Token selection reads only a step env: binding, with comments
# --- stripped first.
make_case misleading_comment "# publisher-targets: issues pull-requests
# GH_TOKEN: \${{ steps.privileged.outputs.token }}
$(token_step)
          permission-issues: write
      - name: Mint a privileged token
        id: privileged
        uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1
        with:
          client-id: \${{ inputs.client_id }}
          private-key: \${{ secrets.app_private_key }}
          permission-issues: write
          permission-pull-requests: write
      - name: Publish
        env:
          GH_TOKEN: \${{ steps.app.outputs.token }}
        run: true"
run_case misleading_comment
[[ "$CASE_STATUS" == 1 ]] ||
  fail "misleading_comment: a commented GH_TOKEN redirected validation (exit $CASE_STATUS)"
grep -qF "step 'app'" <<<"$CASE_STDERR" ||
  fail "misleading_comment: validation must follow the env: binding, not the comment; got: $CASE_STDERR"

# --- A GH_TOKEN mentioned in a run: script is not what the runner exports, so
# --- it must not be read as the binding either.
make_case run_mention "# publisher-targets: issues
$(token_step)
          permission-issues: write
      - name: Publish
        env:
          GH_TOKEN: \${{ steps.app.outputs.token }}
        run: echo \"GH_TOKEN: \${{ steps.other.outputs.token }}\""
run_case run_mention
[[ "$CASE_STATUS" == 0 ]] ||
  fail "run_mention: a GH_TOKEN inside run: must not override the env: binding: $CASE_STDERR"


# --- dr-agents#449 re-review 3: an EARLIER authenticated step must not absorb
# --- validation. Selecting one binding is what kept failing -- anywhere in the
# --- file, then any token step, then the first env: binding. Every GH_TOKEN
# --- binding is now validated, so there is no selection left to mislead.
make_case earlier_binding "# publisher-targets: issues pull-requests
$(token_step)
          permission-issues: write
      - name: Mint a privileged token
        id: privileged
        uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1
        with:
          client-id: \${{ inputs.client_id }}
          private-key: \${{ secrets.app_private_key }}
          permission-issues: write
          permission-pull-requests: write
      - name: An earlier authenticated step
        env:
          GH_TOKEN: \${{ steps.privileged.outputs.token }}
        run: true
      - name: Publish
        env:
          GH_TOKEN: \${{ steps.app.outputs.token }}
        run: true"
run_case earlier_binding
[[ "$CASE_STATUS" == 1 ]] ||
  fail "earlier_binding: an earlier privileged binding absorbed validation (exit $CASE_STATUS)"
grep -qF "step 'app'" <<<"$CASE_STDERR" ||
  fail "earlier_binding: the under-scoped binding must be named; got: $CASE_STDERR"

# --- PROJECT_GH_TOKEN and other suffixed names are not GH_TOKEN bindings. The
# --- real reusable-publish-pr-metadata.yml exports both, so a loose key match
# --- would validate a Projects-scoped token as if it published.
make_case suffixed_key "# publisher-targets: issues
$(token_step)
          permission-issues: write
      - name: Publish
        env:
          GH_TOKEN: \${{ steps.app.outputs.token }}
          PROJECT_GH_TOKEN: \${{ steps.absent.outputs.token }}
        run: true"
run_case suffixed_key
[[ "$CASE_STATUS" == 0 ]] ||
  fail "suffixed_key: PROJECT_GH_TOKEN must not be read as a GH_TOKEN binding: $CASE_STDERR"

# --- The repository's own publishers must satisfy the gate. ------------------
bash "$script" "$root/.github/workflows" ||
  fail "catalog: the repository's own publisher definitions fail the capability gate"

echo "PASS: $(basename "${BASH_SOURCE[0]}")"
