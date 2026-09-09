# Implement-issue contract

## Inputs

Require the working branch created by `start-issue`, the resolved issue
context, and the `plan-implementation` output. Do not implement without a
confirmed branch, issue reference, and test-first plan.

## Steps

1. Apply commit-format and validation guidance discovered from `CONTRIBUTING.md`
   following [contribution-guidance-contract](contribution-guidance-contract.md).
   A missing file is not a blocker. Surface any material conflict with the
   profile before committing.
2. Follow the accepted plan criterion by criterion. For each executable
   behavior change, write or update the planned Red test first and verify its
   failure for the expected reason.
3. Make the smallest Green implementation that passes the planned happy path,
   failure path, relevant edge cases, and regression coverage. Refactor only
   with those tests still passing.
4. For an explicitly non-executable change, run the structural validation named
   in the plan. Do not claim TDD is inapplicable merely to avoid writing tests.
5. After each logical unit, run the profile's quality command. Stop immediately
   if it fails.
6. When executing an authorized spec trio, record each completed task, its
   declared covered criterion IDs, and the result of its `Verification:`
   command. If the trio has no traceability format, report that limitation
   without inventing task coverage.
7. Commit each logical unit with a message that references the issue and
   describes the intent, not the mechanics. Append the adapter's
   `Co-authored-by trailer` from `reviewer-identity.md` to every commit
   message — never the generic model or CLI identity, and never the trailer
   belonging to a different adapter (e.g. a Claudio DR execution must not
   carry the `cody-dr[bot]` trailer and vice versa).
   Use the adapter's commit helper when supplied and inspect the resulting
   commit trailers before pushing; a promise in the message draft is not
   verification. Preserve human co-authors and the user's Git author/signing
   configuration. Co-authorship does not imply cryptographic signing.
8. Do not push, open a PR, or touch files outside the issue's stated scope.

## Output

```md
## Implementation — <issue reference>

**Branch:** `<branch-name>`
**Commits:** N
**Quality command:** <passed|failed at commit N: reason>
**Test-first evidence:** <Red/Green/Refactor evidence per criterion>
**Spec task traceability:** <task ID → covered criterion IDs → verification result, or unavailable: trio lacks traceability format>
**Acceptance criteria:** <all addressed|not yet addressed: criterion>
**Contribution guidance:** <applied: <items> | not found | conflict: <description>>
**Next:** ship-issue
```

Stop and emit a handoff block if the quality command fails or any acceptance
criterion cannot be addressed within the stated scope.
