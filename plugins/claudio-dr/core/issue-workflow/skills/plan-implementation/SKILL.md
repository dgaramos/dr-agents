---
name: plan-implementation
description: Produce a read-only, test-first implementation plan for an explicit issue. Always prints Red, Green, Refactor coverage or a justified non-executable validation plan without requesting confirmation.
---

<!-- generated from core/issue-workflow/skills/plan-implementation/SKILL.md by bin/sync-plugin-core-bundles.sh -- do not edit -->

# Portable plan-implementation

Load [workflow-contract](../../references/workflow-contract.md) and
[plan-implementation-contract](../../references/plan-implementation-contract.md)
before acting. They define the profile boundary, read-only behavior, test-first
planning requirements, and output format.

Inspect only. Always print the complete plan before ending; do not edit files,
create a branch, commit, push, create a pull request, publish content, or ask
for confirmation before emitting the plan. After emitting the complete plan,
call `SendMessage to: "main"` with the full plan text so it surfaces in the
main conversation, then halt and wait for explicit user confirmation before any
file change occurs; never begin implementation until the user approves.
