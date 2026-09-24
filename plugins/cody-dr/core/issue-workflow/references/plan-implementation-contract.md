<!-- generated from core/issue-workflow/references/plan-implementation-contract.md by bin/sync-plugin-core-bundles.sh -- do not edit -->
# Plan-implementation contract

## Purpose

`plan-implementation` turns an explicit issue into an actionable, test-first
implementation plan before any file changes. It is strictly read-only: it may
inspect the issue, profile, repository, and tests, but never edits files,
creates branches, commits, pushes, opens pull requests, or publishes content.

## Steps

1. Load the issue, its acceptance criteria, dependencies, and the target
   profile when available. Inspect the relevant code and existing tests.
2. Map every acceptance criterion to the smallest in-scope change and affected
   files. Mark assumptions, unresolved dependencies, and out-of-scope work;
   do not silently decide them away.
3. For every executable behavior change, define the maximum practical automated
   coverage: happy path, failure path, relevant edge cases, and regression
   coverage. State the exact Red test, Green implementation, and Refactor
   verification steps.
4. For a non-executable change, state `TDD: Not applicable`, explain why, and
   name the strongest available structural validation (for example a document
   check, manifest validation, or contract test).
5. Name the quality commands and the order in which they run. Always emit the
   complete plan; never wait for a confirmation prompt before printing it.
6. After emitting the plan, halt and wait for explicit user confirmation before
   any file in the repository is created, modified, or deleted. Do not begin
   the `implement-issue` phase until the user explicitly approves the plan.
   If the user redirects, adjusts, or cancels, incorporate the feedback and
   re-emit the revised plan before requesting confirmation again.

## Output

```md
## Implementation plan — <issue reference>

**Profile:** <profile name or none>
**Dependencies:** <resolved|blocked: #N, …>
**Scope:** <in-scope summary>
**Out of scope:** <items or none>

### Criterion — <acceptance criterion>

**Files:** `<path>`, …
**TDD:** <Red → Green → Refactor | Not applicable: reason>
**Coverage:** <happy path; failure path; edge cases; regression, or structural validation>
**Steps:**
1. <Red test or structural validator>
2. <minimal Green implementation>
3. <Refactor and rerun commands>

**Risks and assumptions:** <items or none>
**Validation order:** `<command>`, …
**Next:** implement-issue
```

Dependencies or ambiguity remain visible in the printed plan. They block
implementation when material, but never suppress the plan output.
