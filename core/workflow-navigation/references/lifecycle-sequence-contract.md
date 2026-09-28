# Lifecycle sequence contract

## Purpose

This contract states how the catalog's capabilities compose: which precede
which, which are optional, and what decides. It exists because that knowledge
has lived only in the shape of the skill set, so every user has had to infer it.

<!-- bin/check anchor: "does not restate the order inside issue delivery" is a load-bearing phrase matched by bin/check. Do not reword without updating the corresponding grep assertion in bin/check. -->

It covers the decisions no other contract owns: whether to design, whether to
spec, and where to enter. It does not restate the order inside issue delivery.
That belongs to `core/issue-workflow/references/workflow-contract.md`, which
remains the single source of truth for it; a second statement of that order
would drift from the first with nothing reconciling them.

## The spine

    (design) → (spec) → issue → delivery → review → findings

Every stage in parentheses is optional. The unparenthesised stages are the
minimum path: an issue, the delivery of that issue, a review of the result, and
the handling of what the review finds.

## When design comes first

Design discovery precedes spec authoring when the request is about what a user
experiences and the answer is not yet decided — a flow, a screen, an
interaction, a wording that changes behaviour. Specifying first would freeze an
interface nobody has reasoned about, and the spec would then be edited to match
whatever the design turned out to be.

The output is a Design Brief, which is context for spec or issue authoring, not
authorization to write or publish anything.

## When spec comes first

Spec authoring precedes design when the hard part is the rule, not the surface:
a contract, a vocabulary, a boundary, a data shape. Here design has nothing to
resolve until the rule exists, and a Design Brief written first would be
describing a system whose constraints are still open.

## When either is skipped

Skip design when the request changes no user-visible behaviour.

Skip spec when the decision it would record is cheap to reverse. A spec earns
its keep when a choice is expensive to unwind — a vocabulary many files conform
to, a contract other contracts consume, a boundary that changes what is
authorized. When the work is a single change that review can judge whole, a spec
restates the issue at greater length.

Skip both when the change is a defect with a known cause and a bounded fix.

## Clarification and analysis

Clarification runs against an authored spec that is materially ambiguous — where
two readings would produce different implementations. It is not a review pass;
absence of ambiguity is the normal case.

Analysis runs against an authored spec to check it against evidence before work
starts. Drift classification runs against a spec whose implementation has moved
away from it, and answers whether the spec or the implementation is now wrong.

All three read; none of them write.

## Entering in the middle

The spine is a default, not a gate. A user who already has an issue enters at
delivery. One who already has a pull request enters at review. One holding
review findings enters at findings handling.

Entering in the middle is ordinary. The stages skipped were optional or already
done, and a navigation surface says which those were rather than sending the
user back to the start.

## What decides, in one question each

- **Design?** Does this change what a user sees or does?
- **Spec?** Is the decision expensive to reverse?
- **Clarify?** Would two readings of the spec build different things?
- **Analyze?** Is there evidence the spec has not been checked against?
- **Enter where?** What artifact already exists — nothing, a spec, an issue, a
  branch, a pull request, or findings?
