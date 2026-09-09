---
description: Claudio DR implements the changes required by an issue on the working branch, running quality gates and committing in isolation.
---

# Claudio DR implement-issue

Reviewer identity: **Claudio DR** (Claude App reviewer).

For every authorized commit, load `${CLAUDE_PLUGIN_ROOT}/references/reviewer-identity.md` and use
`bash "${CLAUDE_PLUGIN_ROOT}"/scripts/commit.sh <message-file>` after staging
the intended files. Resolve the script from this plugin, not the target repo.
The helper preserves human co-authors, replaces generic model attribution with
this adapter's trailer, and verifies the resulting commit. A verification
failure must be resolved before pushing. This is co-authorship, not a
cryptographic signature; preserve the user's Git author and signing settings.

Load `core/issue-workflow/skills/implement-issue/SKILL.md` and follow its
referenced contracts. Use Claude Code file editing and shell tools for making
changes and running the profile's quality command.

Discover the target profile first with
`core/profile-discovery/references/profile-discovery-contract.md`.

Follow `core/issue-workflow/references/contribution-guidance-contract.md` to
apply commit-format and validation guidance from `CONTRIBUTING.md`. A missing
file is not a blocker; surface any material conflict with the profile before
committing.

## Required TDD execution discipline

For every executable behavior change, perform three discrete, recorded stages:

1. write and run a real failing Red test before implementation code, recording
   why it fails for the intended behavior;
2. make the smallest Green implementation and rerun the focused test; and
3. refactor only after the planned coverage passes, then rerun the criterion's
   validation order and the profile quality command.

The Green coverage must include the happy path, a failure path and at least one
relevant edge case, unless the accepted plan explicitly justifies why a category
does not apply. Record the commands and outcomes in the implementation summary.
The Red test must run before implementation in the working tree; do not create
a standalone failing commit, because the portable quality-gate contract permits
commits only after the logical unit passes.

## Anti-patterns to reject

Do not add implementation and tests together without first observing Red. Do
not call a passing test written after the implementation “Red”. Do not replace
failure-path or edge-case coverage with a happy-path-only assertion. Do not
collapse the three stages into prose, skip the refactor verification, or defer
all validation until the end of the issue. If any executable criterion would do
so, stop and complete its missing stage before continuing.
