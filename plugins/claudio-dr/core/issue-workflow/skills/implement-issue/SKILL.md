---
name: implement-issue
description: Implement the changes required by an issue on the working branch. Makes minimal in-scope changes, runs quality gates after each logical unit, and commits in isolation.
---

<!-- generated from core/issue-workflow/skills/implement-issue/SKILL.md by bin/sync-plugin-core-bundles.sh -- do not edit -->

# Portable implement-issue

Load [workflow-contract](../../references/workflow-contract.md) and
[implement-issue-contract](../../references/implement-issue-contract.md) before
acting. They define profile-owned fields, the quality gate, the publication
boundary, the handoff format, and the implement-issue steps and output.

Keep the diff within
[change-discipline-contract](../../references/change-discipline-contract.md):
the minimum change that answers the issue, no single-use abstraction, no
adjacent edits, and every changed line traceable to the request. Report what
was noticed and left alone as `Observed, not changed:`.

Require a confirmed working branch and issue context from `start-issue`. Stop
and emit a handoff block if the quality command fails or any acceptance
criterion cannot be addressed within the stated scope.

Require the read-only `plan-implementation` output before editing. Follow its
Red → Green → Refactor steps for every executable behavior change and run the
named structural validation only when TDD is explicitly not applicable.
