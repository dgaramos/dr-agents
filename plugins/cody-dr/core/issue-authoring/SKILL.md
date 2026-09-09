---
name: author-issue
description: Draft and optionally publish a well-structured GitHub issue. Publish only when authorized, preferring the adapter App with evidence-based personal fallback when unavailable.
---

# Portable issue authoring

Load [issue-contract](references/issue-contract.md) before drafting. It defines
the mode-detection step, required issue structure, draft-first behavior,
profile-owned fields, the publication boundary, and the post-publication
verification requirement.

Load the target project's profile before authoring. The profile supplies labels,
assignees, milestones, Projects, and any repository issue template to apply. A
missing profile means only known repository guidance and metadata apply; state
unknown fields in the draft summary and still discover the App publisher.

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
