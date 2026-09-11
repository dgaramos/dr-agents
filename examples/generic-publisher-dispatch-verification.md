# Generic publisher dispatch verification

A profile's publisher dispatch declarations are a path-for-path record of the
publisher workflows a project has installed. Nothing about a hand-maintained
list obliges it to track reality, and an agent selecting a publisher trusts it,
so the agreement is verified rather than assumed:

```bash
core/pr-review/scripts/verify-publisher-dispatch.sh \
  example-api/.dr-agents/example-api/PROFILE.md \
  example-api/.github/workflows
```

The verifier takes a profile path and a workflows directory, and compares them
in both directions.

- **Forward.** Every publisher stub named in the profile exists in the
  workflows directory. A declaration pointing at no file is a dispatch that
  fails at use.
- **Reverse.** Every publisher stub installed in the workflows directory is
  named somewhere in the profile. This is the direction that catches real
  drift: a forward-only check passes while an installed publisher goes
  undeclared, so the profile silently understates what the project can do.

Both directions are mandatory. A verifier that checks only the forward
direction reports agreement for a profile that omits publishers entirely.

## Declarations are read as tokens, not as a layout

Profiles do not share one layout. A profile may name its workflows in table
cells, or only in prose bullets further down the file. The verifier extracts
every publisher stub filename from anywhere in the profile text, so both shapes
resolve identically and neither needs to adopt the other's formatting.

## A stub filename is strictly shaped

A publisher stub is named exactly `publish-<token>.yml`, lowercase, with no
spaces. The pattern is strict on purpose, and it decides membership in both
directions:

- A reusable workflow called by a stub, such as
  `reusable-publish-review.yml`, is not itself dispatched as a publisher. It is
  neither declarable nor reported as undeclared.
- A file whose name could never be a stub name — one containing a space, for
  instance — is not a name any profile could declare. It belongs to neither
  direction: it is not counted, and it is not reported as drift.

The verifier prints a `declared: N / installed: N` count and exits non-zero on
any disagreement, naming each offending file and its direction. It takes only
the two paths, so a project wires it into whatever quality gate it already has
without the verifier knowing anything about that project's test framework,
language, or profile location.
