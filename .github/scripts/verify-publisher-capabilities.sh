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
#
# It must further be read from the ONE token step the publishing operation
# actually uses, not from every token step in the file. A definition may mint
# more than one token for different purposes: reusable-publish-pr-metadata.yml
# mints a second, Projects-scoped token whose permissions say nothing about
# what the publisher can do. Unioning them let a write permission on an
# unrelated token satisfy a target the publishing token could not authorize
# against -- the same 403, one indirection further out. The publishing token is
# derived from the `GH_TOKEN: ${{ steps.<id>.outputs.token }}` binding, which
# is what the publishing step actually consumes.
set -euo pipefail

workflows="${1:-.github/workflows}"
failed=0

# Print `key: value` for every `with:` input of each create-github-app-token
# step in the file, with comments stripped. Structural scoping, not text
# search: a line outside such a step's `with:` block is never printed.
# The step id bound to GH_TOKEN is the token the publishing step consumes.
# Deriving it means no new marker to keep in sync, and a definition that binds
# no GH_TOKEN has no publishing token to validate, which is itself a failure.
publishing_token_id() {
  awk '
    # Comments are stripped before any matching. A comment naming a different,
    # privileged token could otherwise redirect validation away from the token
    # the publishing step consumes -- the same class of bypass as matching
    # permission text anywhere in the file.
    {
      line = $0
      sub(/[[:space:]]*#.*$/, "", line)
    }
    line ~ /^[[:space:]]*$/ { next }
    { indent = match(line, /[^ ]/) - 1 }

    # The binding must sit inside a step env: mapping. A GH_TOKEN mentioned in
    # a run: script, a with: input, or prose is not what the runner exports.
    in_env && indent <= env_indent { in_env = 0 }
    line ~ /^[[:space:]]*env:[[:space:]]*$/ { in_env = 1; env_indent = indent; next }

    in_env && line ~ /^[[:space:]]*GH_TOKEN:[[:space:]]*\$\{\{[[:space:]]*steps\./ {
      id = line
      sub(/^.*steps\./, "", id)
      sub(/\.outputs\.token.*$/, "", id)
      print id
      exit
    }
  ' "$1"
}

token_inputs() {
  awk -v want_id="${2:-}" '
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

    # A step id may appear before or after its uses:, so both are tracked and
    # the step is only accepted once its id is known to match.
    line ~ /^[[:space:]]*-?[[:space:]]*id:[[:space:]]*/ {
      seen_id = line
      sub(/^[[:space:]]*-?[[:space:]]*id:[[:space:]]*/, "", seen_id)
    }

    line ~ /uses:[[:space:]]*actions\/create-github-app-token@/ {
      pending = 1; step_indent = indent; next
    }

    pending && line ~ /^[[:space:]]*with:[[:space:]]*$/ {
      pending = 0
      if (want_id != "" && seen_id != want_id) next
      in_with = 1; with_indent = indent; next
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

  # The declared vocabulary is checked before the token is resolved. An unknown
  # target is a marker error and must be reported as one: resolving a token
  # first would answer a question about the marker with a message about tokens.
  unknown_target=0
  for target in $declared_targets; do
    case "$target" in
      issues|pull-requests) ;;
      *)
        echo "publisher-capability: $definition declares unknown target '$target'" >&2
        failed=1
        unknown_target=1 ;;
    esac
  done
  if [[ "$unknown_target" == "1" ]]; then
    continue
  fi

  token_id="$(publishing_token_id "$definition")"
  if [[ -z "$token_id" ]]; then
    echo "publisher-capability: $definition declares targets but binds no GH_TOKEN to an App-token step" >&2
    failed=1
    continue
  fi

  granted="$(token_inputs "$definition" "$token_id")"
  if [[ -z "$granted" ]]; then
    echo "publisher-capability: $definition binds GH_TOKEN to step '$token_id', which is not an actions/create-github-app-token step with inputs" >&2
    failed=1
    continue
  fi

  for target in $declared_targets; do
    case "$target" in
      issues)        required_permission="permission-issues: write" ;;
      pull-requests) required_permission="permission-pull-requests: write" ;;
    esac
    if ! printf '%s\n' "$granted" | grep -qxF "$required_permission"; then
      echo "publisher-capability: $definition is dispatched against $target but its publishing token (step '$token_id') does not request '$required_permission'" >&2
      failed=1
    fi
  done
done

exit "$failed"
