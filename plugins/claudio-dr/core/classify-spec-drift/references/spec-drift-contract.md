<!-- generated from core/classify-spec-drift/references/spec-drift-contract.md by bin/sync-plugin-core-bundles.sh -- do not edit -->
# Portable spec drift contract

## Source and status boundary

Resolve a spec only through an exact, accessible profile-declared source and
path. Never infer a repository, path, or spec status. A profile may opt in to
requiring an accepted spec for authoring or execution; then a missing, `draft`,
`review`, or `superseded` `spec.yaml` status stops that workflow with a
handoff.

## Classification

Classify evidence as exactly one of:

| Classification | Meaning | Smallest permitted next action |
| --- | --- | --- |
| `code-wrong` | Code or tests contradict an accepted spec. | Correct code/tests; do not change requirements by default. |
| `spec-incomplete-or-wrong` | The spec omits or contradicts intended behavior. | Identify affected artifacts and request review; do not resume implementation or rewrite the spec. |
| `implementation-only` | Internal change leaves observable behavior unchanged. | Keep requirements intact unless a recorded decision changes them. |

## Steps

1. State the exact evidence from code, tests, and authorized spec artifacts.
2. Classify the drift and name the smallest permitted next action.
3. Preserve explicit authorization: classification never authorizes a code,
   spec, issue, or pull-request write.
4. If status is required and not accepted, emit a handoff rather than silently
   treating a draft or superseded spec as current.

## Output

```md
## Spec drift — <reference>

**Source:** <authorized location|unavailable: reason>
**Spec status:** <accepted|required but unavailable|not enforced>
**Classification:** <code-wrong|spec-incomplete-or-wrong|implementation-only|not classified>
**Evidence:** <facts and files>
**Next action:** <smallest permitted action>
**Write:** not authorized
**Publication:** not published
```
