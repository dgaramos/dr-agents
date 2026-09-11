#!/usr/bin/env bash
# Guards the fix for the workflow/action version skew in #260.
#
# Before the fix, a reusable publisher reached its scripts through a composite
# action pinned at a literal ref (@workflows-v1) while the workflow itself was
# resolved at the caller's ref (@main). The two came from different commits, and
# `uses:` does not accept expressions, so the action's ref could never be
# derived. Round 2 of docs/spike-reusable-workflow-resolution.md measured that a
# reusable workflow also cannot derive its own ref at runtime.
#
# The remaining guarantee is static: the stub passes the very ref it calls, and
# these tests assert the two agree. That assertion is the fix.
set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

readonly checkout_sha="11d5960a326750d5838078e36cf38b85af677262"
# The publishers that stage catalog files. Two definitions are deliberately
# absent: they are self-contained and need no catalog checkout, so a required
# catalog_ref there would be an input nothing reads.
readonly staging_modes=(pr-metadata pr reply resolve review)
# The other side of that split, asserted rather than merely implied by absence.
# Listing the staging modes alone would let a new self-contained definition grow
# a checkout without any test noticing (dr-agents#269).
readonly self_contained_modes=(issue issue-comment)

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
pass() { echo "ok: $*"; }

# --- A. the composite action is gone, everywhere ---------------------------
if [[ -e .github/actions/catalog-scripts ]]; then
  fail "A: .github/actions/catalog-scripts still exists"
else
  pass "A: composite action directory removed"
fi

if grep -rl "catalog-scripts" .github/workflows plugins/*/workflows >/dev/null 2>&1; then
  fail "A: catalog-scripts still referenced: $(grep -rl 'catalog-scripts' .github/workflows plugins/*/workflows | tr '\n' ' ')"
else
  pass "A: no workflow references the composite action"
fi

# --- B. each staging workflow declares catalog_ref and checks out with it ---
for mode in "${staging_modes[@]}"; do
  wf=".github/workflows/reusable-publish-${mode}.yml"
  [[ -f "$wf" ]] || { fail "B: missing $wf"; continue; }

  if ! ruby -ryaml -e '
    wf = YAML.load_file(ARGV[0])
    inp = wf["on"] || wf[true]
    ci = inp["workflow_call"]["inputs"]["catalog_ref"] rescue nil
    exit 1 unless ci && ci["required"] == true && ci["type"] == "string"
  ' "$wf"; then
    fail "B: $wf does not declare a required string input catalog_ref"
  else
    pass "B: $wf declares required catalog_ref"
  fi

  if ! grep -q "uses: actions/checkout@${checkout_sha}" "$wf"; then
    fail "B: $wf does not pin actions/checkout@${checkout_sha}"
  fi
  if ! grep -q 'ref: \${{ inputs.catalog_ref }}' "$wf"; then
    fail "B: $wf does not check out at inputs.catalog_ref"
  fi
  if ! grep -q 'persist-credentials: false' "$wf"; then
    fail "B: $wf checkout does not set persist-credentials: false"
  fi
done

# --- B2. each self-contained definition stays self-contained ---------------
#
# The absence of a checkout is a property worth a test, not an accident. It is
# what lets these two definitions take no catalog_ref at all, which removes the
# entire class of ref skew this file exists to guard.
for mode in "${self_contained_modes[@]}"; do
  wf=".github/workflows/reusable-publish-${mode}.yml"
  [[ -f "$wf" ]] || { fail "B2: missing $wf"; continue; }

  if grep -q 'actions/checkout' "$wf"; then
    fail "B2: $wf performs a checkout; it is declared self-contained"
  else
    pass "B2: $wf performs no checkout"
  fi
  # Asserted against the parsed input list, not against the word. Both of these
  # definitions explain in a comment why they take no catalog_ref, and a grep
  # for the bare word calls that explanation a violation.
  if ruby -ryaml -e '
    wf = YAML.safe_load(File.read(ARGV[0]), aliases: true)
    on = wf["on"] || wf[true]
    exit((on["workflow_call"]["inputs"] || {}).key?("catalog_ref") ? 1 : 0)
  ' "$wf"; then
    pass "B2: $wf declares no catalog_ref input"
  else
    fail "B2: $wf declares a catalog_ref input; it stages no catalog files"
  fi
  if grep -q 'inputs\.catalog_ref' "$wf"; then
    fail "B2: $wf reads inputs.catalog_ref"
  else
    pass "B2: $wf reads no catalog_ref"
  fi
done

# --- C. every stub passes the same ref it calls ----------------------------
# This is the heart of the fix. A stub that calls @main but passes
# catalog_ref: workflows-v1 would reintroduce the exact skew being removed.
check_stub() {
  local file="$1" expected_ref="$2" role="$3" mode uses_ref given_ref
  uses_ref="$(sed -n 's#^ *uses: dgaramos/dr-agents/\.github/workflows/reusable-publish-\([a-z-]*\)\.yml@\(.*\)$#\1 \2#p' "$file")"
  [[ -n "$uses_ref" ]] || { fail "C: $file does not call a central publisher"; return; }
  mode="${uses_ref%% *}"
  uses_ref="${uses_ref#* }"

  case " ${staging_modes[*]} " in
    *" $mode "*) ;;
    *) pass "C: $file (${mode}) stages no catalog files; catalog_ref not required"; return ;;
  esac

  given_ref="$(sed -n 's#^ *catalog_ref: *\(.*\)$#\1#p' "$file")"
  if [[ -z "$given_ref" ]]; then
    fail "C: $file calls ${mode} at @${uses_ref} but passes no catalog_ref"
    return
  fi
  if [[ "$given_ref" != "$uses_ref" ]]; then
    fail "C: $file calls @${uses_ref} but passes catalog_ref: ${given_ref} (must be identical)"
    return
  fi
  if [[ "$given_ref" != "$expected_ref" ]]; then
    fail "C: $file (${role}) must use ref ${expected_ref}, found ${given_ref}"
    return
  fi
  pass "C: $file pins ${expected_ref} in both uses: and catalog_ref"
}

for f in .github/workflows/publish-*.yml; do check_stub "$f" "main" "catalog dogfooding copy"; done
for f in plugins/*/workflows/publish-*.yml; do check_stub "$f" "workflows-v1" "installed template"; done

# --- D. a single pinned checkout SHA in the publisher definitions ----------
mapfile -t pins < <(grep -rho 'actions/checkout@[A-Za-z0-9.]*' .github/workflows/reusable-publish-*.yml plugins/*/workflows/publish-*.yml .github/workflows/publish-*.yml 2>/dev/null | sort -u)
if [[ "${#pins[@]}" -ne 1 || "${pins[0]}" != "actions/checkout@${checkout_sha}" ]]; then
  fail "D: publisher definitions must use exactly one pin (actions/checkout@${checkout_sha}); found: ${pins[*]:-none}"
else
  pass "D: single pinned checkout across publisher definitions"
fi

# --- E. the guard rejects an empty or malformed ref ------------------------
# The guard has to be inline in the workflow: it runs before the catalog is
# checked out, so it cannot live in a script the checkout would provide. Its
# logic is extracted here and executed against real inputs.
guard="$(ruby -ryaml -e '
  wf = YAML.load_file(".github/workflows/reusable-publish-pr-metadata.yml")
  step = wf["jobs"]["publish"]["steps"].find { |s| s["id"] == "catalog" }
  abort "no step with id catalog" unless step && step["run"]
  print step["run"]
')" || { fail "E: cannot extract the guard step"; guard=""; }

if [[ -n "$guard" ]]; then
  run_guard() {
    CATALOG_REF="$1" GITHUB_OUTPUT="$(mktemp)" GITHUB_STEP_SUMMARY="$(mktemp)" \
      bash -c "$guard" >/dev/null 2>&1
  }
  # happy path
  if run_guard "main"; then pass "E: guard accepts a branch ref"; else fail "E: guard rejected 'main'"; fi
  # edge case: a tag ref must work, or tag promotion breaks
  if run_guard "workflows-v1"; then pass "E: guard accepts a tag ref"; else fail "E: guard rejected 'workflows-v1'"; fi
  # failure path
  if run_guard ""; then fail "E: guard accepted an empty ref"; else pass "E: guard rejects an empty ref"; fi
  if run_guard 'refs/heads/main; rm -rf /'; then fail "E: guard accepted a malformed ref"; else pass "E: guard rejects a malformed ref"; fi
fi

if [[ "$failures" -gt 0 ]]; then
  echo "reusable ref resolution: ${failures} failure(s)" >&2
  exit 1
fi
echo "reusable ref resolution tests passed"
