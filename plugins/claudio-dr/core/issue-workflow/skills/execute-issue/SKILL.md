---
name: execute-issue
description: Orchestrate the full issue-to-change lifecycle: start, test-first planning, implementation, and formal shipping in sequence.
---

<!-- generated from core/issue-workflow/skills/execute-issue/SKILL.md by bin/sync-plugin-core-bundles.sh -- do not edit -->

# Portable execute-issue

Load [workflow-contract](../../references/workflow-contract.md) and
[execute-issue-contract](../../references/execute-issue-contract.md) before
acting. They define the orchestration sequence, authorization boundary, profile
loading rules, handoff format, and final summary output.

Load the target project's profile once at start and pass its context through
all phases. An explicit issue-execution request runs the required lifecycle:
`start-issue` → `plan-implementation` → `implement-issue` → `ship-issue`.
The only human gate is plan approval. After the plan is approved, proceed
through every required phase, including `ship-issue`, without requesting
further confirmation. `ship-issue` must emit its own shipping output before
`execute-issue` reports completion.
