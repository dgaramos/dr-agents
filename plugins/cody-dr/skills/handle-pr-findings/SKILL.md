---
name: handle-pr-findings
description: Cody DR triages actionable pull request findings, applies valid in-scope fixes, validates them, and prepares or publishes thread updates only when explicitly authorized.
---

# Cody DR findings

Reviewer identity: **Cody DR** (Codex App reviewer).

For every authorized commit, load `references/reviewer-identity.md` and use
`bash <installed-plugin-root>/scripts/commit.sh <message-file>` after staging
the intended files. Resolve the script from this plugin, not the target repo.
The helper preserves human co-authors, replaces generic model attribution with
this adapter's trailer, and verifies the resulting commit. A verification
failure must be resolved before pushing. This is co-authorship, not a
cryptographic signature; preserve the user's Git author and signing settings.

Discover the target profile first with
`core/profile-discovery/references/profile-discovery-contract.md`.

Load `core/findings-handling/references/findings-contract.md` before acting.
It defines current-head verification, triage classifications, fix requirements,
out-of-scope deferral via the issue-authoring contract, reply and resolution
behavior, and the outcome summary format. Use `Cody DR` as the reviewer name
in outcome summaries and publication fields.

First produce the contract's complete itemized triage and obtain an explicit
user decision for each finding. Do not fix, create an issue, reply, resolve,
push, or merge based on the triage alone. For each approved fix, make a
dedicated commit and cite it in the eventual thread reply.

Never publish a pull-request review as part of finding triage. Publishing a
review is the exclusive scope of the `review-pr` skill and requires separate
explicit user authorization. Triage ends after fixes are committed and pushed.

When authorized to publish, load `references/reviewer-identity.md` and follow
the publisher-first policy in
`core/pr-review/references/publication-routing-contract.md`. Discover the App
even without a profile. Require evidence before selecting personal fallback
and verify the actual actor and intended thread. An author-verification
failure is a failed publication, never a fallback. Inspect uncertain or partial
dispatch results before retrying; proven token-generation failure before any
mutation follows the routing contract. Never mark a finding resolved based
only on a reply.
