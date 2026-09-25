---
name: ship-issue
description: Claudio DR validates and formally ships a completed implementation in the resolved target repository.
visibility: internal
effects: [writes-workspace, publishes]
gates: [explicit-authorization]
---

# Claudio DR ship-issue

Load `core/issue-workflow/skills/ship-issue/SKILL.md`, including its
`contribution-guidance-contract.md` reference. Resolve the target first with
`core/target-resolution/references/target-resolution-contract.md`,
then discover its profile at the resolved checkout via
`core/profile-discovery/references/profile-discovery-contract.md`.
