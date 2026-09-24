<!-- generated from core/analyze-spec/references/analyze-spec-contract.md by bin/sync-plugin-core-bundles.sh -- do not edit -->
# Portable spec analysis contract

## Inputs and source boundary

Resolve a trio only through one exact, accessible profile-declared `## Spec
source` and authorized path. With a missing, partial, ambiguous, inaccessible,
or unauthorized source, do not infer a repository or path; report it as
unavailable. Read optional `clarifications.md` and a profile or constitution
only when the authorized source declares them.

## Checks

Report evidence for each of these checks:

1. criterion coverage: every declared criterion ID has one or more task links;
2. verification coverage: every task has a safe, non-empty `Verification:`;
3. cross-artifact conflicts: requirements, design, tasks, and clarifications
   do not contradict each other;
4. boundaries: the trio does not contradict loaded profile or constitution
   constraints; and
5. checkpoint readiness: each `## Checkpoint` names a decision and whether it
   is resolved.

For a legacy trio without IDs or links, report traceability unavailable; do not
invent coverage. Never rewrite the trio, execute a task verification command,
or publish analysis.

## Output

```md
## Spec analysis — <trio reference>

**Source:** <authorized location|unavailable: reason>
**Readiness:** <ready|not ready|not analyzed>
**Criterion coverage:** <evidence|unavailable: legacy format>
**Verification coverage:** <evidence>
**Conflicts:** <none|findings>
**Boundaries:** <satisfied|findings>
**Checkpoints:** <ready|blocked: decision>
**Publication:** not published
```
