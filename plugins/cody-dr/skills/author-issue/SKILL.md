---
name: author-issue
description: Cody DR drafts structured GitHub issues and publishes only when authorized, preferring its App with evidence-based fallback.
---

# Cody DR author-issue

Reviewer identity: **Cody DR**. Load
`references/reviewer-identity.md` before using a publisher.

Discover the target profile with
`core/profile-discovery/references/profile-discovery-contract.md`.
Load `core/issue-authoring/SKILL.md` and follow its referenced contract.
Use `Cody DR` in the draft summary.

Apply `core/pr-review/references/publication-routing-contract.md`.
The documented `create-issue` workflow is
`.github/workflows/publish-cody-issue.yml` unless repository guidance supplies
another publisher. Prefer the App and verify `cody-dr[bot]` as the author.
Personal fallback requires evidence of unavailability, never just a missing
profile or a generic error. Announce and verify the actual personal actor.
Preserve template structure and pass known metadata using structured inputs.
