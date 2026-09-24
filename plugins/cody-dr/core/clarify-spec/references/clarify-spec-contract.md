<!-- generated from core/clarify-spec/references/clarify-spec-contract.md by bin/sync-plugin-core-bundles.sh -- do not edit -->
# Portable spec clarification contract

## Inputs and source boundary

Resolve a trio only through one exact, accessible profile-declared `## Spec
source` and authorized path. With a missing, partial, ambiguous, inaccessible,
or unauthorized source, do not infer a repository or path; report it as
unavailable. `clarifications.md` is optional and may be read when present.

## Steps

1. Read `requirements.md`, `design.md`, and `tasks.md` without modifying them.
2. Identify only material ambiguities that block observable behavior, component
   ownership, safety, verification, or a declared checkpoint.
3. For each ambiguity, state the evidence, the decision required, and one
   proposed default. A proposed default is not an implementation decision.
4. State the destination for an approved decision: observable behavior belongs
   in requirements; technical choices belong in design; task sequencing belongs
   in tasks.
5. Do not write the default or resolve a clarification unless the caller
   separately authorizes that exact write.

## Output

```md
## Spec clarification — <trio reference>

**Source:** <authorized location|unavailable: reason>
**Status:** <ready|needs decisions|not analyzed>
### Decision — <short name>
**Evidence:** <files and facts>
**Proposed default:** <explicit default>
**Destination after approval:** <requirements.md|design.md|tasks.md>
**Write:** not authorized
```

**Publication:** not published.
