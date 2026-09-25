<!-- generated from core/surface-metadata/references/surface-metadata-contract.md by bin/sync-plugin-core-bundles.sh -- do not edit -->
# Surface metadata contract

## Purpose

This contract defines what every agent and skill surface declares about itself:
whether it is a public entry point, what it changes, and what confirmation it
requires before it changes it. The declarations are frontmatter in the surface's
own file, beside the behavior they describe, which is what keeps the two from
drifting.

The contract is portable. It defines a vocabulary and its rules, not a target
project's architecture, commands, or review policy. The declarations are
descriptive, not executable: nothing consults them at run time, and nothing
verifies at run time that a surface obeys its own declaration.

## Required fields

Every `SKILL.md` and every agent file declares, in YAML frontmatter:

| Field | Type | Vocabulary |
|---|---|---|
| `name` | string | lowercase, hyphen-separated |
| `description` | string | one line |
| `visibility` | string | `public`, `internal` |
| `effects` | inline list | `read-only`, `writes-workspace`, `publishes` |
| `gates` | inline list | `none`, `approval-checkpoint`, `explicit-authorization` |

`effects` and `gates` are written as inline sequences: `effects: [publishes]`,
`gates: [approval-checkpoint, explicit-authorization]`.

## Visibility

<!-- bin/check anchor: "public", "internal" and "a lifecycle step another surface orchestrates" are load-bearing phrases matched by bin/check. Do not reword without updating the corresponding grep assertions in bin/check. -->

`public` is a documented entry point a user invokes directly. `internal` is a
lifecycle step another surface orchestrates. A surface is not internal merely
because it is rarely invoked; it is internal when another surface owns its
sequencing.

## Effects

<!-- bin/check anchor: "read-only", "writes-workspace", "publishes" and "declares its maximum reach" are load-bearing phrases matched by bin/check. Do not reword without updating the corresponding grep assertions in bin/check. -->

- `read-only` — reads repository or forge state and mutates nothing.
- `writes-workspace` — creates or modifies files, branches, or commits in a
  resolved checkout.
- `publishes` — creates or modifies forge artifacts: issues, pull requests,
  comments, reviews, or thread state.

A surface declares its maximum reach, not its reach on a particular run. A
surface that publishes only after authorization still declares `publishes`,
because a surface that can publish must never read as read-only. The
authorization is described by `gates`, not by omitting the effect.

`read-only` is exclusive: a surface declaring it declares no other effect.

## Gates

<!-- bin/check anchor: "none", "approval-checkpoint", "explicit-authorization" and "requires explicit authorization for a specific act" are load-bearing phrases matched by bin/check. Do not reword without updating the corresponding grep assertions in bin/check. -->

- `none` — proceeds without stopping.
- `approval-checkpoint` — stops mid-flow for user approval before continuing.
- `explicit-authorization` — requires explicit authorization for a specific act
  before performing it.

`none` is exclusive: a surface declaring it declares no other gate.

## The publication implication

<!-- bin/check anchor: "A surface declaring `publishes` declares `explicit-authorization`" is a load-bearing phrase matched by bin/check. Do not reword without updating the corresponding grep assertion in bin/check. -->

A surface declaring `publishes` declares `explicit-authorization` in `gates`.

This is the catalog's publication boundary expressed as a checked property.
Stated only in prose, the boundary holds exactly as long as every surface's text
happens to say so; as a declared pair it fails the quality gate the moment one
surface does not.

## Parity

<!-- bin/check anchor: "Identity differs between adapters; behavior does not." is a load-bearing phrase matched by bin/check. Do not reword without updating the corresponding grep assertion in bin/check. -->

A surface and its counterpart in the other adapter declare the same
`visibility`, `effects`, and `gates`. Identity differs between adapters;
behavior does not. A disagreement is not a platform difference, it is one of
the two declarations being wrong.

## Enforcement

The set of surfaces is derived from the tree, never enumerated. A surface added
without declarations fails the gate for that reason, not because a list was
forgotten. Per-surface validation runs before the parity comparison, so a
malformed file is reported as malformed rather than as a mismatch against its
counterpart, and every violation is reported rather than only the first.
