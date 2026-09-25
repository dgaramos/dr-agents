---
name: execute-issue
description: Claudio DR orchestrates an approved issue plan through formal shipping.
visibility: public
effects: [writes-workspace, publishes]
gates: [approval-checkpoint, explicit-authorization]
---

# Claudio DR execute-issue

Reviewer identity: **Claudio DR** (Claude App reviewer).

Load `core/issue-workflow/skills/execute-issue/SKILL.md` and follow its
referenced contracts. The explicit issue-execution request authorizes the full
lifecycle through the required `ship-issue` phase; do not stop to request a
second confirmation before shipping.

Discover the target profile first with
`core/profile-discovery/references/profile-discovery-contract.md`.
