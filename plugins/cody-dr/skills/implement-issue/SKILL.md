---
name: implement-issue
description: Cody DR implements the changes required by an issue on the working branch, running quality gates and committing in isolation.
---

# Cody DR implement-issue

Reviewer identity: **Cody DR** (Codex App reviewer).

For every authorized commit, load `references/reviewer-identity.md` and use
`bash <installed-plugin-root>/scripts/commit.sh <message-file>` after staging
the intended files. Resolve the script from this plugin, not the target repo.
The helper preserves human co-authors, replaces generic model attribution with
this adapter's trailer, and verifies the resulting commit. A verification
failure must be resolved before pushing. This is co-authorship, not a
cryptographic signature; preserve the user's Git author and signing settings.

Load `core/issue-workflow/skills/implement-issue/SKILL.md` and follow its
referenced contracts. Use Codex file editing and shell tools for making
changes and running the profile's quality command.

Discover the target profile first with
`core/profile-discovery/references/profile-discovery-contract.md`.

Follow `core/issue-workflow/references/contribution-guidance-contract.md` to
apply commit-format and validation guidance from `CONTRIBUTING.md`. A missing
file is not a blocker; surface any material conflict with the profile before
committing.
