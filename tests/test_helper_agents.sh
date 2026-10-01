#!/usr/bin/env bash
set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly agents_entrypoint="$repository_root/bin/agents"

readonly helpers=(
  "$repository_root/plugins/claudio-dr/agents/claudio-helper.md"
  "$repository_root/plugins/cody-dr/agents/cody-helper.md"
)

for helper in "${helpers[@]}"; do
  content="$(<"$helper")"
  for required in \
    'Mode 1' \
    'Mode 2' \
    'Mode 3' \
    '.dr-agents/*/PROFILE.md' \
    'bin/install --repo' \
    'bin/install --status' \
    'AGENTS.md' \
    'Cody DR'; do
    if [[ "$content" != *"$required"* ]]; then
      echo "FAIL: $(basename "$helper") is missing required helper behavior: $required" >&2
      exit 1
    fi
  done
done

# Every `agents <command>` a helper agent recommends must be a command that
# bin/agents actually dispatches.
#
# The valid set is DERIVED from bin/agents rather than listed here. A literal
# assertion is what let both helper agents keep advising `agents download`
# after #484 removed that subcommand: the test passed precisely because the
# helpers recommended a command that no longer existed (dr-agents#487). Same
# precedent as bin/install deriving its stub set from plugins/*/workflows/ and
# verify-publisher-dispatch.sh comparing a profile against .github/workflows/.
#
# Read the `case` dispatch, not the usage prose: the prose is itself
# hand-maintained text and can drift from the implementation.
valid_commands="$(
  sed -n '/^case "\$command" in$/,/^esac$/p' "$agents_entrypoint" |
    sed -n 's/^[[:space:]]*\([A-Za-z|_-]*\)).*/\1/p' |
    tr '|' '\n' |
    sed 's/^-*//' |
    sed '/^$/d' |
    sort -u
)"

if [[ -z "$valid_commands" ]]; then
  echo "FAIL: derived no subcommands from the dispatch in bin/agents; the derivation is broken, not the helpers" >&2
  exit 1
fi

# Only inline code spans count as a citation. Bare prose such as "both helper
# agents are installed" is not a command recommendation.
cited_commands_of() {
  grep -o '`agents [^`]*`' "$1" |
    sed 's/^`agents //; s/`$//' |
    awk '{ print $1 }' |
    sed '/^$/d' |
    sort -u
}

previous_helper=""
previous_cited=""

for helper in "${helpers[@]}"; do
  cited="$(cited_commands_of "$helper" || true)"

  if [[ -z "$cited" ]]; then
    echo "FAIL: $(basename "$helper") cites no \`agents <command>\` at all; it is the installation entrypoint and must recommend one" >&2
    exit 1
  fi

  while IFS= read -r command; do
    if ! grep -qxF "$command" <<<"$valid_commands"; then
      echo "FAIL: $(basename "$helper") recommends 'agents $command', which bin/agents does not dispatch" >&2
      echo "       commands bin/agents dispatches: $(tr '\n' ' ' <<<"$valid_commands")" >&2
      exit 1
    fi
  done <<<"$cited"

  # Bidirectional adapter parity: the two helpers must recommend the same
  # commands, so a fix to one cannot silently skip the other.
  if [[ -n "$previous_helper" && "$cited" != "$previous_cited" ]]; then
    echo "FAIL: helper agents disagree on which agents commands to recommend" >&2
    echo "       $(basename "$previous_helper"): $(tr '\n' ' ' <<<"$previous_cited")" >&2
    echo "       $(basename "$helper"): $(tr '\n' ' ' <<<"$cited")" >&2
    exit 1
  fi

  previous_helper="$helper"
  previous_cited="$cited"
done

echo "helper agent tests passed"
