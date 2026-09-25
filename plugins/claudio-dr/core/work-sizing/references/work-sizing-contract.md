<!-- generated from core/work-sizing/references/work-sizing-contract.md by bin/sync-plugin-core-bundles.sh -- do not edit -->
# Work sizing contract

## Purpose

This contract defines the unit of work: how much one issue or one task holds.
Structure and traceability contracts specify what a well-formed issue or task
looks like and how criteria map to work, but neither states how much work one
of them carries. Without that, both drift toward one fragment per criterion,
because splitting is free and silent while merging requires an argument.

The contract is portable. It defines a sizing judgement, not a target project's
architecture, commands, issue metadata, or review policy. It sets no numeric
threshold: a ratio of tasks to criteria is evidence for a reader, never a gate.

## Unit of work

<!-- bin/check anchor: "what is changed, reviewed, and reverted together", "name every criterion it covers" and "Traceability is a property of the mapping" are load-bearing phrases matched by bin/check. Do not reword without updating the corresponding grep assertions in bin/check. -->

A unit of work is what is changed, reviewed, and reverted together. Size an
issue or a task to that, then name every criterion it covers. Traceability is a
property of the mapping, never of the count.

A single unit may satisfy many criteria. Covering five criteria in one task is
not a traceability defect as long as the task names all five; splitting them
into five tasks does not add traceability, it only adds boundaries.

## Justifying a boundary

<!-- bin/check anchor: "state what forces the boundary", "expensive to reverse", "Absent one of those, merge." and "where a reviewer can read it" are load-bearing phrases matched by bin/check. Do not reword without updating the corresponding grep assertions in bin/check. -->

Before splitting, state what forces the boundary: a decision that is expensive
to reverse, a dependency that cannot be satisfied in one change, or a review
that cannot be done as one. Absent one of those, merge. State it in one line,
in the issue or in the task, where a reviewer can read it.

The statement is an output, not private reasoning. An unwritten justification
cannot be reviewed or challenged, so a boundary whose forcing reason was never
written down is an unjustified boundary.

## Signals to merge

<!-- bin/check anchor: "Signals to merge, not to split" is a load-bearing phrase matched by bin/check. Do not reword without updating the corresponding grep assertion in bin/check. -->

Signals to merge, not to split: fragments touching the same file in the same
change; a `blocked-by` chain whose links have no independent value; a task
count approaching the criterion count.

None of these is conclusive on its own. A small piece of work can legitimately
run at one task per criterion when the criteria genuinely describe separable
changes. Each signal is a prompt to apply the justification rule above, not a
verdict.

## Relationship to traceability

Traceability requires that every criterion be covered by some unit and that
every unit name what it covers. It says nothing about how many units exist.
Merging two tasks that each named their criteria produces one task naming both,
with traceability intact. Consumers of this contract keep their own coverage
rules and reach this file for the sizing judgement alone.
