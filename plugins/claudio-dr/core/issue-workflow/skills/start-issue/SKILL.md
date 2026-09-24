---
name: start-issue
description: Begin an issue-to-change lifecycle. Loads the profile, resolves the issue, checks dependencies, and creates the working branch using profile-defined branch naming.
---

<!-- generated from core/issue-workflow/skills/start-issue/SKILL.md by bin/sync-plugin-core-bundles.sh -- do not edit -->

# Portable start-issue

Load [workflow-contract](../../references/workflow-contract.md) and
[start-issue-contract](../../references/start-issue-contract.md) before acting.
They define profile-owned fields, the quality gate, the publication boundary,
the handoff format, and the start-issue steps and output.

Load the target project's profile before resolving the issue. Stop and emit a
handoff block if any blocking dependency is unresolved or required profile
values are missing.

Resolve the target first with
`core/target-resolution/references/target-resolution-contract.md`,
then discover its profile with
`core/profile-discovery/references/profile-discovery-contract.md` at the
resolved checkout. Run every git command inside that checkout.
