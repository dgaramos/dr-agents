---
name: plan-issue
description: Claudio DR produces a read-only issue plan and waits for approval.
visibility: public
effects: [read-only]
gates: [approval-checkpoint]
---

# Claudio DR plan-issue

Load `core/issue-workflow/skills/plan-issue/SKILL.md`, discover the profile via `core/profile-discovery/references/profile-discovery-contract.md`. After producing the plan, call `SendMessage to: "main"` with the full plan text so it surfaces in the main conversation, then stop and wait for explicit user confirmation before any implementation begins.
