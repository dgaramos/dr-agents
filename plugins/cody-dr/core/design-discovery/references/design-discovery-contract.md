<!-- generated from core/design-discovery/references/design-discovery-contract.md by bin/sync-plugin-core-bundles.sh -- do not edit -->
# Design-discovery contract

## Purpose

Design discovery turns a client-facing request, existing interface, or supplied
design reference into an evidence-grounded, implementation-ready Design Brief.
It is portable: it does not assume a browser, image generator, repository UI,
or any platform-specific tool.

## Inputs and evidence

The input may be a request, existing UI, screenshot, mockup, prototype,
specification, draft issue, or a combination of those sources. Inspect the
available evidence before making recommendations.

Separate facts observed in the supplied material from assumptions. When
information is missing, state the assumption and list the open question; do
not invent users, product requirements, local UI patterns, or technical
constraints. When no inspectable existing UI is available, describe the result
as an initial direction rather than an assessment of local patterns.

## Steps

1. Determine whether the request has material UX/UI impact. For purely
   technical, trivial, or narrowly mechanical work, explain why design
   discovery is not needed and return a concise `not applicable` result.
2. Assess supplied evidence or critique the supplied proposal. Identify the
   users, task or user flow, current friction, constraints, and unknowns.
3. Produce a concrete representation of the proposed experience using the
   strongest capability available: annotated existing UI, wireframe, structured
   textual layout, generated image, prototype, or another clearly described
   equivalent. If visual inspection or generation is unavailable, provide a
   useful non-visual representation and disclose the limitation.
4. Produce the complete Design Brief described below.
5. Return the brief and handoff without mutating project or external state.

## Design Brief

<!-- bin/check anchor: "## Design Brief" is a load-bearing phrase matched by bin/check. Do not rename this heading without updating the corresponding grep assertion in bin/check. -->

The output must contain these sections:

- **Context and evidence:** the request, sources inspected, and observations.
- **Users and problem:** intended users, their goal, and the UX problem.
- **Flows and states:** the affected flow plus applicable loading, empty,
  error, success, disabled, and recovery states.
- **Constraints and unknowns:** constraints, explicit assumptions, open
  questions, and non-goals.
- **Proposed direction:** interaction and visual direction, with rationale.
- **Proposal representation:** the artifact type, its content or location, and
  any capability limitation that affected it.
- **Accessibility and responsiveness:** relevant semantics, keyboard/focus,
  contrast, motion, content scaling, breakpoints, and device considerations.
- **Implementation direction:** components, behaviors, content, and acceptance
  signals a developer can use without rediscovering the rationale.
- **Success criteria:** observable user-experience outcomes or measurements.
- **Handoff:** concise context suitable for `author-issue`, `spec`,
  `plan-implementation`, or an existing issue.

Only include states and accessibility concerns relevant to the request, but
explicitly say when a category is not applicable.

## Handoff boundary

<!-- bin/check anchor: "`author-issue` may" is a load-bearing phrase matched by bin/check. Do not reword this sentence without updating the corresponding grep assertion in bin/check. -->

The Design Brief is context, not a publication command. `author-issue` may
incorporate a supplied brief into a structured issue body. `spec` may use it as
optional input for portable spec authoring. Implementation and planning may use
it as prior design direction. The designer never creates the issue, opens a
pull request, comments, uploads an artifact, or changes code by default.

## Publication boundary

Without explicit authorization for a specific external action, finish with:

```md
## Design discovery

**Publication:** not published
```

<!-- bin/check anchor: "**Publication:** not published" is a load-bearing phrase matched by bin/check. Do not reword this line without updating the corresponding grep assertion in bin/check. -->

Explicit authorization for design discovery alone does not authorize issue
creation, comments, code changes, image uploads, or any other external action.
