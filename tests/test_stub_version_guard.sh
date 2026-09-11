#!/usr/bin/env bash
# Guards the outdated-stub detector from dr-agents#268.
#
# A stub is a file copied into the consumer. When a central definition gains an
# input a stub must pass, an older stub does not pass it, the input arrives
# empty, and nothing says so. That is the same silent-failure class as the four
# defects the #260 migration itself hit.
#
# The detector compares the stub's own version against a MINIMUM literal
# embedded in each definition. The issue text proposed comparing against the
# catalog version staged at `catalog_ref`; this diverges from it deliberately:
#
#   - comparing against the *current* catalog version would fire on every
#     routine version bump, in consumers that are perfectly correct, and a guard
#     that alarms when all is well is ignored within two releases -- which
#     reintroduces the silence by another route; and
#   - `reusable-publish-issue.yml` performs no checkout and takes no
#     `catalog_ref`, a property tests/test_reusable_ref_resolution.sh actively
#     asserts. A literal needs no staged catalog, so the issue publisher needs
#     no exception at all.
#
# The tests below execute the REAL guard script, extracted from the definition,
# rather than a reimplementation of it. A copy would pass while the shipped
# block was wrong.
set -euo pipefail

readonly root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

readonly definitions=(.github/workflows/reusable-publish-*.yml)

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
pass() { echo "ok: $*"; }

# The catalog version every stub marker and every `stub_version:` literal must
# agree with. Read from the same manifest bin/check and bin/install read.
catalog_version() {
  local manifest="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.version' "$manifest"
  else
    grep '"version"' "$manifest" | head -1 \
      | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
  fi
}
readonly claudio_ver="$(catalog_version plugins/claudio-dr/.claude-plugin/plugin.json)"
readonly cody_ver="$(catalog_version plugins/cody-dr/.codex-plugin/plugin.json)"

# --- A. every definition declares the input ---------------------------------
#
# Not required, and defaulted to empty. A required input would hard-fail every
# consumer installed today at dispatch time, including the ones that are fine.
for wf in "${definitions[@]}"; do
  if ! ruby -ryaml -e '
    wf = YAML.safe_load(File.read(ARGV[0]), aliases: true)
    on = wf["on"] || wf[true]
    i = (on["workflow_call"]["inputs"] || {})["stub_version"]
    exit 1 if i.nil?
    exit 1 if i["required"]
    exit 1 unless i["default"] == ""
    exit 1 unless i["type"] == "string"
  ' "$wf" 2>/dev/null; then
    fail "A: $wf does not declare a non-required, empty-defaulted string input 'stub_version'"
  else
    pass "A: $(basename "$wf") declares stub_version"
  fi
done

# --- B. the minimum literal agrees across all six ---------------------------
#
# A partial bump would make the guard lie about what it requires, which is worse
# than not having it. Same reasoning as the `definition_release` marker.
minimums=()
for wf in "${definitions[@]}"; do
  m="$(sed -n 's/^ *minimum_stub_version="\([0-9.]*\)"$/\1/p' "$wf" | head -1)"
  if [[ -z "$m" ]]; then
    fail "B: $wf embeds no minimum_stub_version literal"
  else
    minimums+=("$m")
  fi
done
if [[ "${#minimums[@]}" == "${#definitions[@]}" ]]; then
  unique="$(printf '%s\n' "${minimums[@]}" | sort -u | wc -l | tr -d ' ')"
  if [[ "$unique" != "1" ]]; then
    fail "B: definitions disagree on minimum_stub_version: $(printf '%s ' "${minimums[@]}")"
  else
    pass "B: all ${#definitions[@]} definitions require stub v${minimums[0]}"
  fi
  # The minimum can never exceed what the catalog can actually install, or every
  # freshly installed stub would be rejected on arrival.
  lowest="$(printf '%s\n%s\n' "${minimums[0]}" "$claudio_ver" \
    | sort -t. -k1,1n -k2,2n -k3,3n | head -1)"
  if [[ "$lowest" != "${minimums[0]}" ]]; then
    fail "B: minimum v${minimums[0]} exceeds the catalog version v${claudio_ver}"
  else
    pass "B: minimum v${minimums[0]} is installable from catalog v${claudio_ver}"
  fi
fi

# --- C. every stub passes its own version -----------------------------------
#
# The invariant that matters: the `stub_version:` literal equals the `#
# <agent>-dr: v` marker in that same file. Without it the guard reports a
# version the stub does not have -- a silent failure inside the silent-failure
# detector.
for stub in .github/workflows/publish-*.yml plugins/*/workflows/publish-*.yml; do
  case "$(basename "$stub")" in
    publish-claudio-*) agent=claudio-dr; expected="$claudio_ver" ;;
    publish-cody-*)    agent=cody-dr;    expected="$cody_ver" ;;
    *) continue ;;
  esac
  marker="$(sed -n "s/^# ${agent}: v\(.*\)$/\1/p" "$stub" | head -1)"
  passed="$(sed -n 's/^ *stub_version: *\(.*\)$/\1/p' "$stub" | head -1)"
  if [[ -z "$passed" ]]; then
    fail "C: $stub passes no stub_version to the central definition"
  elif [[ "$passed" != "$marker" ]]; then
    fail "C: $stub passes stub_version: ${passed} but its marker says v${marker}"
  elif [[ "$marker" != "$expected" ]]; then
    fail "C: $stub marker v${marker} disagrees with the catalog v${expected}"
  else
    pass "C: $(dirname "$stub")/$(basename "$stub") passes its own v${passed}"
  fi
done

# --- D. the real guard script behaves ---------------------------------------
#
# Extract the first step's `run:` block and execute it. This is the shipped
# code, not a reimplementation.
guard_script="$(mktemp)"
summary_file="$(mktemp)"
trap 'rm -f "$guard_script" "$summary_file"' EXIT

ruby -ryaml -e '
  wf = YAML.safe_load(File.read(ARGV[0]), aliases: true)
  print wf["jobs"]["publish"]["steps"][0]["run"].to_s
' .github/workflows/reusable-publish-review.yml > "$guard_script" 2>/dev/null || true

if [[ ! -s "$guard_script" ]]; then
  fail "D: could not extract the guard script from reusable-publish-review.yml"
else
  # A leaked `${{ }}` expression would make the extracted block unrunnable here
  # and, more importantly, means the step reads an input outside `env:`.
  if grep -q '\${{' "$guard_script"; then
    fail "D: the guard step interpolates a workflow expression; pass inputs through env:"
  else
    pass "D: the guard step is pure shell, inputs arrive through env:"
  fi

  # stub_version, expected exit code, expected substring in the run output,
  # expected substring in the step summary.
  cases=(
    "0.1.31|0|stub version: 0.1.31|stub version"
    "0.2.0|0|stub version: 0.2.0|stub version"
    "1.0.0|0|stub version: 1.0.0|stub version"
    # The trap. A string comparison puts 0.1.9 ABOVE 0.1.31 and lets an
    # outdated stub through silently. This is the case most likely to be got
    # wrong and the least visible when it is.
    "0.1.9|1|stub-outdated|stub-outdated"
    "0.0.1|1|stub-outdated|stub-outdated"
    "0.1.30|1|stub-outdated|stub-outdated"
    # Forward-only: a stub predating the guard cannot pass the input that would
    # report it. Non-fatal, but loud in BOTH channels -- a warning nobody reads
    # is the same silence under another name.
    "|0|stub-version-unknown|stub-version-unknown"
    # Malformed rather than compared numerically and silently passing.
    "abc|1|stub-version-malformed|stub-version-malformed"
    "v0.1.31|1|stub-version-malformed|stub-version-malformed"
    "0.1|1|stub-version-malformed|stub-version-malformed"
  )
  for entry in "${cases[@]}"; do
    IFS='|' read -r version want_code want_out want_summary <<< "$entry"
    : > "$summary_file"
    set +e
    out="$(STUB_VERSION="$version" GITHUB_STEP_SUMMARY="$summary_file" \
      bash "$guard_script" 2>&1)"
    code=$?
    set -e
    label="stub_version='${version}'"
    if [[ "$code" != "$want_code" ]]; then
      fail "D: ${label} exited ${code}, expected ${want_code} -- ${out}"
      continue
    fi
    if ! grep -qF "$want_out" <<< "$out"; then
      fail "D: ${label} run output lacks '${want_out}': ${out}"
      continue
    fi
    if ! grep -qF "$want_summary" "$summary_file"; then
      fail "D: ${label} step summary lacks '${want_summary}'"
      continue
    fi
    pass "D: ${label} -> exit ${code}, reported in both channels"
  done
fi

# --- E. the guard is byte-identical across the six definitions --------------
#
# Six inline copies of one block is the shape #260 exists to collapse, and it is
# tolerated here only because a reusable workflow cannot share shell with
# another without a checkout -- which the issue publisher does not have. What
# keeps six copies honest is this assertion, the same bargain the
# `definition_release` marker already makes.
reference=""
for wf in "${definitions[@]}"; do
  block="$(ruby -ryaml -e '
    wf = YAML.safe_load(File.read(ARGV[0]), aliases: true)
    print wf["jobs"]["publish"]["steps"][0]["run"].to_s
  ' "$wf" 2>/dev/null || true)"
  if [[ -z "$reference" ]]; then
    reference="$block"
  elif [[ "$block" != "$reference" ]]; then
    fail "E: $wf's guard step diverges from the other definitions"
  fi
done
[[ "$failures" == "0" ]] && pass "E: all ${#definitions[@]} definitions carry an identical guard step"

if [[ "$failures" != "0" ]]; then
  echo "${failures} failure(s)" >&2
  exit 1
fi
echo "all stub version guard checks passed"
