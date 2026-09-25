# Generic example — surface metadata

A catalog with two adapters, `alpha` and `beta`, each shipping the same skills
under its own identity. Every surface declares the five fields from
`core/surface-metadata/references/surface-metadata-contract.md`.

## A read-only public entry point

```yaml
---
name: inspect-change
description: Alpha reports what a change does without altering anything.
visibility: public
effects: [read-only]
gates: [none]
---
```

`read-only` is exclusive, so no other effect appears. Nothing stops, so `gates`
is `[none]`.

## An internal lifecycle step

```yaml
---
name: prepare-branch
description: Alpha creates the working branch for an orchestrated delivery.
visibility: internal
effects: [writes-workspace]
gates: [none]
---
```

`internal` because another surface owns its sequencing, not because it is rarely
invoked.

## A publishing surface

```yaml
---
name: deliver-change
description: Alpha publishes the prepared change to the forge.
visibility: internal
effects: [writes-workspace, publishes]
gates: [explicit-authorization]
---
```

`publishes` requires `explicit-authorization`. The surface is read-only until
authorized, and still declares `publishes`: a surface declares its maximum
reach, because one that can publish must never read as read-only.

## A surface that stops for approval

```yaml
---
name: propose-plan
description: Alpha proposes a plan and waits before anything proceeds.
visibility: public
effects: [read-only]
gates: [approval-checkpoint]
---
```

A gate without an effect is ordinary: stopping for approval says nothing about
whether the surface mutates.

## Parity

`beta`'s counterparts differ only in identity:

```yaml
---
name: inspect-change
description: Beta reports what a change does without altering anything.
visibility: public
effects: [read-only]
gates: [none]
---
```

The three behavioral fields are identical. A disagreement between counterparts
is one of the two declarations being wrong, not a platform difference.

## What the declarations do not claim

Nothing verifies at run time that `inspect-change` in fact mutates nothing. The
declaration is a statement the gate holds the catalog to, not a sandbox.
