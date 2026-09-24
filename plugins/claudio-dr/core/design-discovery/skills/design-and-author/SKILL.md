---
name: design-and-author
description: Chain design discovery directly into issue authoring. Runs design-discovery once and passes its output as context to author-issue without a separate manual invocation.
---

<!-- generated from core/design-discovery/skills/design-and-author/SKILL.md by bin/sync-plugin-core-bundles.sh -- do not edit -->

# Portable design-and-author

Load [design-discovery-contract](../../references/design-discovery-contract.md)
and [issue-contract](../../../../core/issue-authoring/references/issue-contract.md)
before acting.

## Steps

1. Run design discovery following the full portable
   `core/design-discovery/SKILL.md` contract. Produce the complete Design Brief
   and handoff. Do not exit or wait for a manual step before continuing.
2. Pass the Design Brief handoff directly as the `author-issue` context input.
   Do not re-run design discovery. Do not ask the caller to copy the handoff
   manually.
3. Run `author-issue` following `core/issue-authoring/SKILL.md`. Use the
   handoff as the primary context alongside any caller-supplied issue title or
   additional requirements.
4. Return the completed issue draft and the publication boundary as defined in
   the issue-authoring contract. Do not publish the issue unless the caller
   separately authorizes that exact publication.

## Handoff boundary

The chained output is a publication-ready issue draft, not a published issue.
The publication boundary from both the design-discovery contract and the
issue-authoring contract applies: the designer never publishes by default.

## Publication boundary

Without explicit authorization for a specific external action, finish with:

```md
## Design discovery

**Publication:** not published
```
