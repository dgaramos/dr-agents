---
name: author-issue
description: Draft and optionally publish a well-structured GitHub issue. Publish only when authorized, preferring the adapter App with evidence-based personal fallback when unavailable.
---

# Portable issue authoring

Load [issue-contract](references/issue-contract.md) before drafting. It defines
the mode-detection step, required issue structure, draft-first behavior,
profile-owned fields, the publication boundary, and the post-publication
verification requirement.

Resolve the target repository before loading any profile, per
`core/target-resolution/references/target-resolution-contract.md`. An issue URL
or an `owner/repository` reference in the request selects the target; the
current directory is the target only when the request names neither.

Load the resolved target's profile before authoring. The profile supplies labels,
assignees, milestones, Projects, and any repository issue template to apply. A
missing profile — at the checkout or because the target is `remote-only` — means
only known repository guidance and metadata apply; state unknown fields in the
draft summary and still discover the App publisher for the target. Never apply
the current directory's profile to another target.

Before drafting, run the mode-detection step from the issue-contract:

1. Classify the input as `bug`, `feature`, `chore`, or `spike`.
2. Execute the mode-specific pre-draft behavior (investigation, discovery
   questions, or scope assessment) as defined in the contract.
3. Then produce the complete structured draft.

When the caller supplies a Design Brief from `design-discovery`, treat its
evidence, direction, constraints, and handoff as issue context. Preserve its
open questions and assumptions; do not silently present them as settled
requirements or re-run design discovery unless the caller asks.

Do not publish the issue or request external state changes until the user
explicitly authorizes it.
