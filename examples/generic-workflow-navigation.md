# Generic example — workflow navigation

A catalog installed as the `alpha` adapter. The user asks what is available.

## Listing

The guide derives the set from the installed root, so this is what is installed
now, not what was written down when the guide was authored:

```
Public entry points
  inspect-change   read-only                      no gate
  propose-plan     read-only                      stops for approval
  deliver-work     writes-workspace, publishes    requires explicit authorization

Internal lifecycle steps
  prepare-branch   writes-workspace               no gate
  apply-change     writes-workspace               no gate

Invoke a skill as <platform syntax>; invoke an agent by its name.
```

`prepare-branch` and `apply-change` are listed, not hidden. A user who cannot
see the steps `deliver-work` orchestrates cannot judge what invoking it will do.

## Describing one surface

```
deliver-work
  Visibility  public
  Effects     writes-workspace, publishes
  Gates       explicit-authorization
  Declared in <root>/skills/deliver-work/SKILL.md

  This surface publishes. It requires explicit authorization for the specific
  act before performing it.
```

Every line comes from declared frontmatter. The guide does not say how
`deliver-work` runs, in what order, or under what conditions it branches — none
of that is declared anywhere, so none of it is claimed. It names the file.

## A question about sequence

> Should I run the designer or the spec first?

```
Design first when the request changes what a user sees or does, and the answer
is not yet decided. Spec first when the hard part is the rule rather than the
surface — a contract, a vocabulary, a boundary.

Yours changes a payment screen's wording and error states, so: design first.

Next: <invocation for design discovery>
```

The answer names an invocation. It does not run it, and it did not inspect the
repository to decide — it used the lifecycle contract and what the user said.

## A question the guide declines

> Which of these should I run on my current branch?

```
I can say which capability fits a situation you describe, but I do not read
your branches, pull requests, or working state to choose. Tell me what exists —
nothing, a spec, an issue, a branch, a pull request, or findings — and I will
name where to enter.
```

Reading project state to form a recommendation is a different capability with a
different boundary. The guide describes the catalog, not the user's project.

## What the guide never does

It never invokes a surface it describes. A navigation surface that could launch
what it lists would reach every publishing operation in the catalog while
carrying none of the authorization each one requires.
