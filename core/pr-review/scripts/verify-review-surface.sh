#!/usr/bin/env bash
# Verify the published review surface against the portable review contract.
#
# `review-contract.md` is the single source of truth for what a finding and a
# summary look like. `reporting.md` keeps only the category and class tables and
# points at the contract. Those tables are the template anchors: when one file's
# anchor set changes and the other's does not, the two files silently disagree
# about what ships, which is exactly the drift this script exists to catch.
#
# The anchor sets are derived from the tables themselves rather than compared
# against a hardcoded list, because a hardcoded list passes the day a category
# is added to both files and is then wrong about what the files actually say.
#
# The findings contract is checked too, because it is the other core file that
# tells a workflow what to post. It must emit the implementer role marker and
# point at the canonical template rather than restate it: two core files
# defining one template is the drift this script exists to prevent, moved one
# layer up.
#
# It also enforces the properties of the published body: it never states its own
# publication status (that belongs to the manifest and the terminal summary),
# the re-review prior-head rule ignores body-less review events, and the
# re-review preamble names the review it supersedes.
#
# Finally it enforces the scannable summary: the body leads with the verdict
# strip and its severity badges, the strip stays inside a rendered budget, the
# required Next step follows it, every scope/checks/limits field sits inside the
# collapsed block, the Checks line is trimmed to CI and local gates, the three
# section size gates are stated, and no confidence percentage reaches the
# reader while the gate and the manifest record remain.
set -euo pipefail

[[ $# == 5 ]] || {
  echo "usage: verify-review-surface.sh CONTRACT_PATH REPORTING_PATH EXAMPLE_PATH FINDINGS_PATH PROFILE_CONTRACT_PATH" >&2
  exit 2
}
contract_path="$1"
reporting_path="$2"
example_path="$3"
findings_path="$4"
profile_contract_path="$5"

for path in "$contract_path" "$reporting_path" "$example_path" "$findings_path" \
  "$profile_contract_path"; do
  [[ -r "$path" ]] || { echo "not readable: $path" >&2; exit 2; }
done

violations=0
violation() { echo "review surface: $1" >&2; violations=$((violations + 1)); }

# ---------------------------------------------------------------------------
# Template anchors
# ---------------------------------------------------------------------------

# Extract the first cell of every body row of the Markdown table whose header
# row contains $2. Cells are normalised (backticks stripped, lowercased) so the
# two files may differ in presentation without counting as divergence.
table_keys() {
  local path="$1" header="$2" columns="${3:-1}"
  awk -v header="$header" -v columns="$columns" '
    index($0, "|") == 1 && index($0, header) > 0 { in_table = 1; next }
    in_table && /^\| *-+/ { seen_rule = 1; next }
    in_table && seen_rule && index($0, "|") != 1 { in_table = 0; seen_rule = 0 }
    in_table && seen_rule {
      line = $0
      sub(/^\| */, "", line)
      count = split(line, cells, / *\| */)
      key = ""
      for (i = 1; i <= columns && i <= count; i++) {
        gsub(/`/, "", cells[i])
        gsub(/^ +| +$/, "", cells[i])
        key = (key == "" ? cells[i] : key " | " cells[i])
      }
      if (key != "") print tolower(key)
    }
  ' "$path" | sort -u
}

compare_anchors() {
  local label="$1" header="$2" columns="$3"
  local contract_keys reporting_keys difference
  contract_keys="$(table_keys "$contract_path" "$header" "$columns")"
  reporting_keys="$(table_keys "$reporting_path" "$header" "$columns")"

  if [[ -z "$contract_keys" ]]; then
    violation "$contract_path defines no $label anchors"
    return
  fi
  if [[ -z "$reporting_keys" ]]; then
    violation "$reporting_path defines no $label anchors"
    return
  fi

  difference="$(comm -3 <(echo "$contract_keys") <(echo "$reporting_keys") || true)"
  if [[ -n "$difference" ]]; then
    violation "the $label anchors diverge between $contract_path and $reporting_path:"
    while IFS= read -r line; do
      [[ -n "${line// /}" ]] || continue
      if [[ "$line" == $'\t'* ]]; then
        echo "  only in $reporting_path: ${line#	}" >&2
      else
        echo "  only in $contract_path: $line" >&2
      fi
    done <<<"$difference"
  fi
}

compare_anchors "category" "Category" 1
compare_anchors "class/badge" "Class" 2

# ---------------------------------------------------------------------------
# One source of truth for the templates
# ---------------------------------------------------------------------------

if ! grep -qF '**Evidence:**' "$contract_path"; then
  violation "$contract_path does not define the finding template"
fi
if ! grep -qF '## Review —' "$contract_path"; then
  violation "$contract_path does not define the review summary template"
fi
if grep -qF '**Evidence:**' "$reporting_path"; then
  violation "$reporting_path re-defines the finding template; it belongs only in $contract_path"
fi
if grep -qF '## Review —' "$reporting_path"; then
  violation "$reporting_path re-defines the summary template; it belongs only in $contract_path"
fi
if ! grep -qF 'review-contract.md' "$reporting_path"; then
  violation "$reporting_path does not point at $contract_path"
fi

# ---------------------------------------------------------------------------
# The published body never states its own publication status
# ---------------------------------------------------------------------------

# A published-body field run is the block of consecutive `**Field:**` lines that
# follows a `## Review —` or `## Re-review —` heading. Restricting the check to
# those runs keeps prose that legitimately discusses publication status from
# being reported as a published-body field.
# The scan continues through the collapsed `<details>` block that #342 moved the
# scope, checks and limits fields into. An earlier version stopped at the first
# line that was not a field, which was correct while every field was a sibling
# of the heading and silently wrong the moment they moved inside the block: a
# `Publication:` field shipped inside `<details>` would have read as a clean
# body. It still stops at the first line of real content — a heading, a table,
# or a fence — so prose that legitimately discusses publication status is not
# mistaken for a published-body field.
published_body_fields() {
  awk '
    /^## (Review|Re-review) —/ { in_body = 1; next }
    in_body && /^\*\*/ { print; next }
    in_body && NF == 0 { next }
    in_body && /^<\/?(details|summary)/ { next }
    in_body { in_body = 0 }
  ' "$1"
}

if published_body_fields "$contract_path" | grep -qF 'Publication:'; then
  violation "$contract_path keeps a Publication field in the published body; publication status belongs to the manifest and the terminal summary"
fi
if grep -qF 'Publication:' "$example_path"; then
  violation "$example_path contains a Publication field; the published body must not state its own publication status"
fi

# ---------------------------------------------------------------------------
# Re-review prior-head rule and superseded review
# ---------------------------------------------------------------------------

if ! grep -qF 'body-less' "$contract_path"; then
  violation "$contract_path does not state that the prior-head lookup ignores body-less review events"
fi
if ! grep -qF 'Superseded:' "$contract_path"; then
  violation "$contract_path re-review preamble does not carry the Superseded field"
fi

# ---------------------------------------------------------------------------
# Scannable summary: verdict first, next step, collapsed scope block
# ---------------------------------------------------------------------------

# The acceptance signal is rendered lines, not source lines, so the strip is
# checked for both position and length: a strip that wraps costs the reader the
# same first screen that a misordered one does.
readonly verdict_strip_budget=200

summary_field_run() {
  awk '
    /^## Review —/ { in_body = 1; next }
    in_body && /^\*\*/ { print; next }
    in_body && NF == 0 { next }
    in_body && /^<\/?(details|summary)/ { print; next }
    in_body { in_body = 0 }
  ' "$contract_path"
}

field_run="$(summary_field_run)"

if [[ -z "$field_run" ]]; then
  violation "$contract_path defines no review summary field run"
else
  first_field="$(head -n 1 <<<"$field_run")"
  if [[ "$first_field" != '**Verdict:**'* ]]; then
    violation "the review summary does not lead with the verdict strip; first field is: $first_field"
  fi
  for badge in '🔴 Critical' '🟠 Major' '🟡 Minor' 'Merge risk'; do
    if [[ "$first_field" != *"$badge"* ]]; then
      violation "the verdict strip does not carry '$badge'"
    fi
  done
  strip_length="$(printf '%s' "$first_field" | wc -c | tr -d ' ')"
  if ((strip_length > verdict_strip_budget)); then
    violation "the verdict strip is too long for its rendered budget: ${strip_length} bytes exceeds ${verdict_strip_budget}"
  fi

  if ! grep -qF '**Next step:**' <<<"$field_run"; then
    violation "the review summary does not carry the required Next step field"
  fi

  # Everything that is not the verdict strip or the next step belongs inside the
  # collapsed block, which starts at the <details> line of the run.
  collapsed_start="$(grep -n '^<details>' <<<"$field_run" | head -n 1 | cut -d: -f1 || true)"
  if [[ -z "$collapsed_start" ]]; then
    violation "the review summary has no collapsed scope block"
  else
    if ! grep -qF '<summary>Scope, checks and limits</summary>' "$contract_path"; then
      violation "the collapsed scope block's <summary> does not name its content"
    fi
    open_fields="$(head -n $((collapsed_start - 1)) <<<"$field_run")"
    collapsed_fields="$(tail -n +"$collapsed_start" <<<"$field_run")"
    for field in 'Scope:' 'Reviewed head:' 'Profile:' 'Language:' 'Checks:' \
      'Risk axes:' 'Thread updates:'; do
      if grep -qF "**$field" <<<"$open_fields"; then
        violation "the $field field is above the verdict's collapsed block; it belongs inside 'Scope, checks and limits'"
      elif ! grep -qF "**$field" <<<"$collapsed_fields"; then
        violation "the collapsed scope block does not carry the $field field"
      fi
    done

    # Scoped to the emitted field, not the file: the contract is written in
    # English and uses the word "source" throughout its own prose, so a
    # whole-file grep would pass while the rendered field said only `pt-BR`.
    language_line="$(grep -F '**Language:**' <<<"$collapsed_fields" | head -n 1)"
    if [[ -n "$language_line" && "$language_line" != *'(source:'* ]]; then
      violation "the emitted Language field carries no source token; a language with no stated origin is not auditable: $language_line"
    fi

    checks_line="$(grep -F '**Checks:**' <<<"$collapsed_fields" | head -n 1)"
    if [[ "$checks_line" != *'CI: '* || "$checks_line" != *'Local: '* ]]; then
      violation "the Checks line is not trimmed to CI and local gate counts: $checks_line"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Section size gates
# ---------------------------------------------------------------------------

while IFS='|' read -r gate label; do
  grep -qE "^Emit the ${gate}" "$contract_path" ||
    violation "$contract_path states no size gate for the ${label}"
done <<'GATES'
Walkthrough|Walkthrough
Behavior map|Behavior map
Pre-merge|Pre-merge checks table
GATES

# ---------------------------------------------------------------------------
# Review language (dr-agents#349)
# ---------------------------------------------------------------------------

# Read only the `### Review language` section's own body. Every token below is
# an ordinary English word that appears elsewhere in this contract, so a
# whole-file grep would report a rule the contract does not actually state.
review_language_section="$(awk '
  /^### Review language/ { in_section = 1; next }
  in_section && /^#+ / { in_section = 0 }
  in_section { print }
' "$contract_path")"

if [[ -z "${review_language_section// /}" ]]; then
  violation "$contract_path states no Review language rule for user-facing prose"
else
  while IFS='|' read -r token label; do
    grep -qF "source: \`${token}\`" <<<"$review_language_section" ||
      violation "the Review language resolution order does not record the ${label} source as 'source: ${token}'"
  done <<'SOURCES'
profile|profile declaration
README|repository README
default|English fallback
SOURCES

  grep -qF 'first source' <<<"$review_language_section" ||
    violation "the Review language section does not state that the first declaring source wins"
  grep -qF 'extensible' <<<"$review_language_section" ||
    violation "the Review language section does not state that the source order is extensible"
  for fixed in 'badges' 'section headings' 'field labels' 'SHAs'; do
    grep -qF "$fixed" <<<"$review_language_section" ||
      violation "the Review language section does not keep ${fixed} in English"
  done
fi

# The profile contract declares the key and points at the canonical order; it
# must not carry a second copy of that order.
if ! grep -qF '`Language:`' "$profile_contract_path"; then
  violation "$profile_contract_path does not document the optional Language key"
fi
if ! grep -qF 'review-contract.md' "$profile_contract_path"; then
  violation "$profile_contract_path does not point at the canonical Review language resolution order in review-contract.md"
fi
if grep -qF 'source: `default`' "$profile_contract_path"; then
  violation "$profile_contract_path restates the Review language resolution order; it belongs only in $contract_path"
fi

# ---------------------------------------------------------------------------
# Thread reply anatomy (dr-agents#347, #348)
# ---------------------------------------------------------------------------

# A reply template missing one of its fields is not a shorter reply; it is a
# reply that has lost the property the field carried — the verified head, the
# audible severity disagreement, or the declared thread action.
for reply_field in 'Verified on' 'Severity (' 'Status:'; do
  if ! grep -qF "**${reply_field}" "$contract_path"; then
    violation "$contract_path thread reply template does not carry the '${reply_field}' field"
  fi
done

if ! grep -qF "display name" "$contract_path"; then
  violation "$contract_path does not state that a reply must not open with the reviewer's display name"
fi

if ! grep -qF 'Fix applied' "$contract_path"; then
  violation "$contract_path does not define the implementer role marker 'Fix applied'"
fi
if ! grep -qF 'never proof of resolution' "$contract_path"; then
  violation "$contract_path does not exclude implementer replies from resolution evidence"
fi

# The findings contract emits the marker by pointing at the canonical template.
# Restating the template here is what the pointer requirement prevents.
if ! grep -qF 'Fix applied' "$findings_path"; then
  violation "$findings_path does not emit the implementer role marker"
fi
if ! grep -qF 'review-contract.md' "$findings_path"; then
  violation "$findings_path does not point at the canonical reply template in review-contract.md"
fi

# ---------------------------------------------------------------------------
# The AI-agent prompt block is optional and evidence-gated (dr-agents#351)
# ---------------------------------------------------------------------------

# Exactly one block, not at least one: a second block elsewhere would carry its
# own looser gate and silently undo the gate below.
prompt_blocks="$(grep -cF '<summary>Prompt for AI agents</summary>' "$contract_path" || true)"
if ((prompt_blocks == 0)); then
  violation "$contract_path defines no AI-agent prompt block"
elif ((prompt_blocks > 1)); then
  violation "$contract_path defines $prompt_blocks AI-agent prompt blocks; exactly one gated block may exist"
fi

# Scoped to the block's own text: prose elsewhere in the contract that happens
# to use the word does not make the emitted prompt say it, and the emitted
# prompt is the only copy a future agent reads.
prompt_block_text="$(awk '
  /<summary>Prompt for AI agents<\/summary>/ { in_block = 1; next }
  in_block && /^<\/details>/ { in_block = 0 }
  in_block { print }
' "$contract_path")"
if ! grep -qF 'untrusted' <<<"$prompt_block_text"; then
  violation "the AI-agent prompt block's own text does not mark the finding data as untrusted"
fi
if ! grep -qF 'one-hunk' "$contract_path"; then
  violation "$contract_path does not gate the AI-agent prompt block on a verified one-hunk fix"
fi
if ! grep -qF 'never required' "$contract_path"; then
  violation "$contract_path does not state that a committable suggestion block is never required"
fi

# ---------------------------------------------------------------------------
# Confidence is reviewer-internal, not reader-facing
# ---------------------------------------------------------------------------

evidence_line="$(grep -F '**Evidence:**' "$contract_path" | head -n 1)"
if [[ "$evidence_line" == *confidence* ]]; then
  violation "the published finding template still renders a confidence value: $evidence_line"
fi
if grep -qE 'confidence: *[0-9<]' "$example_path"; then
  violation "$example_path renders a confidence percentage in a published finding"
fi
if ! grep -qF '>= 80/100' "$contract_path"; then
  violation "$contract_path no longer states the >= 80/100 confidence gate"
fi
if ! grep -qF 'non-published `confidence`' "$contract_path"; then
  violation "$contract_path does not record confidence in the publication manifest"
fi

if ((violations > 0)); then
  echo "review surface: $violations violation(s)" >&2
  exit 1
fi

echo "review surface check: ok"
