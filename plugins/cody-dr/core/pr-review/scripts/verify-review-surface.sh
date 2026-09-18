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
# It also enforces three properties of the published body: it never states its
# own publication status (that belongs to the manifest and the terminal
# summary), the re-review prior-head rule ignores body-less review events, and
# the re-review preamble names the review it supersedes.
set -euo pipefail

[[ $# == 3 ]] || {
  echo "usage: verify-review-surface.sh CONTRACT_PATH REPORTING_PATH EXAMPLE_PATH" >&2
  exit 2
}
contract_path="$1"
reporting_path="$2"
example_path="$3"

for path in "$contract_path" "$reporting_path" "$example_path"; do
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
published_body_fields() {
  awk '
    /^## (Review|Re-review) —/ { in_body = 1; next }
    in_body && /^\*\*/ { print; next }
    in_body && NF == 0 { next }
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

if ((violations > 0)); then
  echo "review surface: $violations violation(s)" >&2
  exit 1
fi

echo "review surface check: ok"
