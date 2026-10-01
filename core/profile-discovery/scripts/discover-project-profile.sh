#!/usr/bin/env bash
set -euo pipefail

# Exit statuses, in the order a caller should reason about them:
#   0 with a path on stdout   exactly one profile was accepted; use it
#   0 with nothing at all     genuine absence; proceed with generic rules
#   0 with a stderr advisory  nothing accepted, but a profile-shaped file sits
#                             outside .dr-agents/; proceed, and report it
#   3                         ambiguous project profiles (unchanged)
#   4                         nothing accepted, and at least one profile-shaped
#                             candidate inside .dr-agents/ was rejected
#   64                        usage error
#
# stdout carries one meaning only: the path of an accepted profile. A rejected
# candidate is never printed there, because a caller that captures stdout would
# use it as a profile path.

root=""
if [[ "${1:-}" == "--root" ]]; then
  root="${2:-}"
  [[ -n "$root" ]] || { echo "--root requires a directory" >&2; exit 64; }
  shift 2
fi
[[ $# -eq 0 ]] || { echo "usage: discover-project-profile.sh [--root DIRECTORY]" >&2; exit 64; }

if [[ -z "$root" ]]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
root="$(cd "$root" && pwd)"

# The accepting search is unchanged and deliberately strict: exactly
# <root>/.dr-agents/<project>/PROFILE.md, case-sensitive, at that one depth.
# Widening it would start accepting files that are not profiles. Only the
# candidate scan below is wider, and it never accepts anything.
profiles=()
if [[ -d "$root/.dr-agents" ]]; then
  while IFS= read -r profile; do
    profiles+=("$profile")
  done < <(find "$root/.dr-agents" -mindepth 2 -maxdepth 2 -type f -name PROFILE.md -print | LC_ALL=C sort)
fi

case "${#profiles[@]}" in
  1) printf '%s\n' "${profiles[0]}" ; exit 0 ;;
  0) ;;
  *) printf 'ambiguous project profiles:\n%s\n' "$(printf '%s\n' "${profiles[@]}")" >&2; exit 3 ;;
esac

# Nothing was accepted. Before reporting that as a genuine absence, look for a
# profile-shaped file in a place this script does not accept, so a near miss is
# distinguishable from an empty repository instead of producing the same silence.
#
# A wide candidate scan can produce false positives, and a false positive is
# worse than today's silence: it fires on a repository that is working. The two
# locations are therefore treated differently on purpose.
#
#   Inside .dr-agents/ the intent is unambiguous. That directory exists for this
#   catalog and nobody puts an unrelated PROFILE.md in it, so a rejected
#   candidate there is a misplacement to fix and it earns a non-zero status.
#
#   At the repository root the intent is not established at all. PROFILE.md is an
#   ordinary filename in projects that have nothing to do with this catalog, so
#   failing on it would break discovery for correct repositories. It is reported
#   on stderr at exit 0: distinguishable from absence, as the requirement asks,
#   without turning a working repository into a failure.
inside_candidates=()
outside_candidates=()

if [[ -d "$root/.dr-agents" ]]; then
  while IFS= read -r candidate; do
    relative="${candidate#"$root/.dr-agents/"}"
    name="${candidate##*/}"
    # Depth is counted in path separators remaining after the prefix: 0 means the
    # file sits directly in .dr-agents/, 1 means the canonical <project>/ level.
    separators="${relative//[^\/]/}"
    depth=$(( ${#separators} + 1 ))
    if (( depth == 1 )); then
      inside_candidates+=("$candidate — not nested in a project directory; expected .dr-agents/<project>/PROFILE.md")
    elif (( depth > 2 )); then
      inside_candidates+=("$candidate — nested too deeply; expected .dr-agents/<project>/PROFILE.md")
    elif [[ "$name" != "PROFILE.md" ]]; then
      inside_candidates+=("$candidate — filename case does not match PROFILE.md")
    fi
  done < <(find "$root/.dr-agents" -mindepth 1 -type f -iname 'profile.md' -print | LC_ALL=C sort)
fi

while IFS= read -r candidate; do
  outside_candidates+=("$candidate — outside .dr-agents/; expected .dr-agents/<project>/PROFILE.md")
done < <(find "$root" -mindepth 1 -maxdepth 1 -type f -iname 'profile.md' -print | LC_ALL=C sort)

if (( ${#inside_candidates[@]} + ${#outside_candidates[@]} == 0 )); then
  exit 0
fi

# Built as one array before expansion: `"${empty[@]}"` is an unbound-variable
# error under `set -u` in bash 3.2, which is the system bash on macOS.
report=()
if (( ${#inside_candidates[@]} > 0 )); then report+=("${inside_candidates[@]}"); fi
if (( ${#outside_candidates[@]} > 0 )); then report+=("${outside_candidates[@]}"); fi

{
  printf 'no project profile accepted; rejected project profile candidates:\n'
  printf '%s\n' "${report[@]}"
} >&2

if (( ${#inside_candidates[@]} > 0 )); then
  exit 4
fi
exit 0
