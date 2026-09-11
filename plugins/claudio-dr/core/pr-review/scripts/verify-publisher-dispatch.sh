#!/usr/bin/env bash
# Verify a profile's publisher dispatch declarations against the publisher
# workflows actually installed, in both directions.
#
# A forward-only check (declared -> file exists) passes while installed
# publishers go undeclared, which is the drift this script exists to catch.
# Both directions are therefore mandatory and neither is optional.
#
# Declarations are extracted as tokens from the whole profile text rather than
# parsed out of one table layout, because profiles do not share a layout: some
# name workflows in table cells, others only in prose. A layout-specific parser
# silently reports zero declarations for the other shape.
set -euo pipefail

[[ $# == 2 ]] || {
  echo "usage: verify-publisher-dispatch.sh PROFILE_PATH WORKFLOWS_DIR" >&2
  exit 2
}
profile_path="$1"
workflows_dir="$2"
[[ -r "$profile_path" ]] || { echo "profile is not readable: $profile_path" >&2; exit 2; }
[[ -d "$workflows_dir" ]] || { echo "workflows directory not found: $workflows_dir" >&2; exit 2; }

# A publisher stub filename is exactly `publish-<lowercase-token>.yml`. The
# pattern is strict on purpose. A file in the workflows directory that looks
# like a stub but does not match this shape -- a name containing a space, for
# instance -- is not a name any profile could declare, so it belongs to neither
# direction: it is neither counted nor reported. The anchor also excludes
# `reusable-publish-*.yml`, which are called by stubs and are never dispatched
# as publishers themselves.
readonly stub_name='^publish-[a-z0-9-]+\.yml$'

# Candidates are matched with a leading run of name characters so that a token
# inside `reusable-publish-review.yml` yields the full name and is then
# rejected by the anchored filter, instead of matching the `publish-review.yml`
# substring as a declaration.
declared="$(
  grep -oE '[a-z0-9-]*publish-[a-z0-9-]+\.yml' "$profile_path" |
    grep -E "$stub_name" | sort -u || true
)"

installed="$(
  find "$workflows_dir" -maxdepth 1 -type f -name '*.yml' -exec basename {} \; |
    grep -E "$stub_name" | sort -u || true
)"

count() { [[ -z "$1" ]] && echo 0 || printf '%s\n' "$1" | wc -l | tr -d ' '; }

status=0

# Forward: every declared publisher must be installed.
missing="$(comm -23 <(printf '%s' "$declared") <(printf '%s' "$installed"))"
if [[ -n "$missing" ]]; then
  while IFS= read -r file; do
    echo "declared in profile but not installed in $workflows_dir: $file" >&2
  done <<<"$missing"
  status=1
fi

# Reverse: every installed publisher must be declared.
undeclared="$(comm -13 <(printf '%s' "$declared") <(printf '%s' "$installed"))"
if [[ -n "$undeclared" ]]; then
  while IFS= read -r file; do
    echo "installed in $workflows_dir but not declared in profile: $file" >&2
  done <<<"$undeclared"
  status=1
fi

echo "publisher dispatch: declared: $(count "$declared") / installed: $(count "$installed")"
exit "$status"
