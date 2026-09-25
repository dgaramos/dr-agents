#!/usr/bin/env bash
# Verify that every reusable publisher mode can authorize against the target
# types it declares.
#
# A publisher mode declares its target types with a `# publisher-targets:`
# marker, and its App token must request a write permission for each one.
# dr-agents#447: the comment publisher was declared, installed, correctly
# named, and returned 403 on every pull-request target because its token
# requested issues:write alone. The existing dispatch verification is a
# PRESENCE check -- declared mode maps to an installed file -- and a present,
# correctly-named publisher that cannot authorize against half its targets is
# exactly what it cannot see.
#
# Both sets are derived from the workflow files: the declared targets from the
# marker, the granted permissions from the `with:` inputs of the
# actions/create-github-app-token step. Nothing here enumerates modes, so a
# publisher added without a marker fails for lacking one.
#
# The permission must be read from the token step's inputs and not from the
# file as a whole. An unscoped text search over the definition is satisfied by
# the same words in a YAML comment, a documentation string, or an unrelated
# step -- so the original 403 could regress while the gate stayed green.
set -euo pipefail

workflows="${1:-.github/workflows}"
failed=0

# Print `key: value` for every `with:` input of each create-github-app-token
# step in the file, with comments stripped. Structural scoping, not text
# search: a line outside such a step's `with:` block is never printed.
token_inputs() {
  awk '
    # Strip comments before any matching, so commented-out text can never look
    # like an input. App-token inputs are unquoted words, so a "#" here always
    # starts a comment.
    {
      line = $0
      sub(/[[:space:]]*#.*$/, "", line)
    }
    line ~ /^[[:space:]]*$/ { next }
    { indent = match(line, /[^ ]/) - 1 }

    # Leaving the with: block ends the step.
    in_with && indent <= with_indent { in_with = 0; pending = 0 }

    # A line at or above the step key indent ends a step still awaiting its
    # with: block.
    pending && indent < step_indent { pending = 0 }

    line ~ /uses:[[:space:]]*actions\/create-github-app-token@/ {
      pending = 1; step_indent = indent; next
    }

    pending && line ~ /^[[:space:]]*with:[[:space:]]*$/ {
      in_with = 1; with_indent = indent; pending = 0; next
    }

    in_with {
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      print line
    }
  ' "$1"
}

shopt -s nullglob
definitions=("$workflows"/reusable-publish-*.yml)
shopt -u nullglob

for definition in "${definitions[@]}"; do
  declared_targets="$(sed -n 's/^# publisher-targets:[[:space:]]*//p' "$definition")"
  if [[ -z "$declared_targets" ]]; then
    echo "publisher-capability: $definition declares no '# publisher-targets:' marker" >&2
    failed=1
    continue
  fi

  granted="$(token_inputs "$definition")"
  if [[ -z "$granted" ]]; then
    echo "publisher-capability: $definition declares targets but has no actions/create-github-app-token step with inputs" >&2
    failed=1
    continue
  fi

  for target in $declared_targets; do
    case "$target" in
      issues)        required_permission="permission-issues: write" ;;
      pull-requests) required_permission="permission-pull-requests: write" ;;
      *)
        echo "publisher-capability: $definition declares unknown target '$target'" >&2
        failed=1
        continue 2 ;;
    esac
    if ! printf '%s\n' "$granted" | grep -qxF "$required_permission"; then
      echo "publisher-capability: $definition is dispatched against $target but its App token does not request '$required_permission'" >&2
      failed=1
    fi
  done
done

exit "$failed"
