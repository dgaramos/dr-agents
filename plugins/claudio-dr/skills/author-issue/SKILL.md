---
name: author-issue
description: Claudio DR drafts structured GitHub issues and publishes only when authorized, preferring its App with evidence-based fallback.
visibility: public
effects: [publishes]
gates: [explicit-authorization]
---

# Claudio DR author-issue

Reviewer identity: **Claudio DR**. Load
`${CLAUDE_PLUGIN_ROOT}/references/reviewer-identity.md` before using a publisher.

Resolve the target repository first with
`core/target-resolution/references/target-resolution-contract.md`: an issue URL
or `owner/repository` in the request selects it, and the current directory only
when neither is given. Then discover that target's profile with
`core/profile-discovery/references/profile-discovery-contract.md` and report its
origin. In `remote-only` mode, read the issue template with
`gh api repos/<target>/contents/...` and declare `Profile: none (remote-only)`.
Load `core/issue-authoring/SKILL.md` and follow its referenced contract.
Use `Claudio DR` in the draft summary.

Apply `core/pr-review/references/publication-routing-contract.md`, selecting
the publisher against the resolved target with
`core/pr-review/scripts/select-publisher.sh <target> <workflow>`.
The documented `create-issue` workflow is
`.github/workflows/publish-claudio-issue.yml` unless repository guidance supplies
another publisher. Prefer the App and verify `claudio-dr[bot]` as the author.
Personal fallback requires evidence of unavailability, never just a missing
profile or a generic error. Announce and verify the actual personal actor.
Preserve template structure and pass known metadata using structured inputs.
