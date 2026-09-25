---
name: start-issue
description: Cody DR begins the issue-to-change lifecycle in the resolved target repository. Loads the profile, resolves the issue, checks dependencies, and creates the working branch.
visibility: internal
effects: [writes-workspace]
gates: [none]
---

# Cody DR start-issue

Reviewer identity: **Cody DR** (Codex App reviewer).

Load `core/issue-workflow/skills/start-issue/SKILL.md` and follow its
referenced contracts.

**Platform-specific detail (Codex only):** use Codex shell and file tools for
branch creation as documented in the target profile's platform notes, if
any. This instruction is scoped to the Codex platform. It is intentionally not mirrored in the Claudio DR adapter, which uses Claude Code worktree mechanics for the same step.

Resolve the target first with
`core/target-resolution/references/target-resolution-contract.md`,
then discover its profile at the resolved checkout with
`core/profile-discovery/references/profile-discovery-contract.md`. Create the
branch in that checkout, never in the current directory.

Follow `core/issue-workflow/references/contribution-guidance-contract.md` to
inspect `CONTRIBUTING.md` before branch creation. A missing file is not a
blocker; surface any material conflict with the profile and request direction.
