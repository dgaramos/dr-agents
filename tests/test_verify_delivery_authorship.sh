#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${VERIFY_SCRIPT:-$root/.github/scripts/verify-delivery-authorship.sh}"

fail() { echo "FAIL: $*" >&2; exit 1; }
cases=0

run() {
  set +e
  CASE_STDOUT="$(bash "$script" "$@" 2>/tmp/vda_err)"
  CASE_STATUS=$?
  set -e
  CASE_STDERR="$(cat /tmp/vda_err)"
}

accepts() { # name, then args
  local name="$1"; shift
  run "$@"
  [ "$CASE_STATUS" -eq 0 ] || fail "$name: expected accept, got $CASE_STATUS ($CASE_STDERR)"
  cases=$((cases + 1))
}

rejects() { # name, expected-message-fragment, then args
  local name="$1" want="$2"; shift 2
  run "$@"
  [ "$CASE_STATUS" -ne 0 ] || fail "$name: expected reject, was accepted"
  printf '%s' "$CASE_STDERR" | grep -qF "$want" \
    || fail "$name: rejected for the wrong reason; wanted '$want', got: $CASE_STDERR"
  cases=$((cases + 1))
}

# A: the regression itself -- a delivery branch opened by a personal account.
rejects A "delivery PR authorship check failed" \
  "361-feat/scannable-review-summary" "dgaramos" ""

# B: the same branch published by the App, in `app/<slug>` shape.
accepts B "360-fix/correct-published-review-surface" "app/claudio-dr" ""

# C: the same actor in `<slug>[bot]` shape, which other endpoints report.
accepts C "360-fix/correct-published-review-surface" "claudio-dr[bot]" ""

# D: the Cody adapter is equally valid -- the check is not Claudio-specific.
accepts D "362-feat/reply-anatomy" "cody-dr[bot]" ""

# E: a non-delivery branch is out of scope, even from a personal account.
accepts E "fix/report-pr-publisher-actor" "dgaramos" ""

# F: every allowed Conventional Commit type is a delivery branch.
for t in feat fix docs refactor chore test build ci; do
  rejects "F-$t" "delivery PR authorship check failed" "12-$t/slug" "dgaramos" ""
done

# G: the documented escape hatch exempts a deliberate human PR.
accepts G "363-feat/review-prose-language" "dgaramos" "core,human-delivery"

# H: a label that merely contains the exempt word must not exempt.
#    Guards against the check being loosened to a substring match.
rejects H "delivery PR authorship check failed" \
  "363-feat/review-prose-language" "dgaramos" "human-delivery-request"

# I: an unrelated label does not exempt.
rejects I "delivery PR authorship check failed" \
  "363-feat/review-prose-language" "dgaramos" "core,enhancement"

# J: the rejection must name the branch and the actor, so the handoff is
#    actionable rather than a bare failure.
run "361-feat/scannable-review-summary" "dgaramos" ""
printf '%s' "$CASE_STDERR" | grep -qF "361-feat/scannable-review-summary" \
  || fail "J: rejection does not name the branch"
printf '%s' "$CASE_STDERR" | grep -qF "dgaramos" \
  || fail "J: rejection does not name the actor"
cases=$((cases + 1))

# K: an unknown branch shape is not silently treated as delivery.
accepts K "dependabot/npm_and_yarn/foo-1.2.3" "dependabot[bot]" ""

rm -f /tmp/vda_err
echo "delivery authorship tests passed ($cases cases)"
