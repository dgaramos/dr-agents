# Workflow navigation contract

## Purpose

This contract defines how the catalog describes itself: what an inventory of
agents and skills contains, where it comes from, and the boundary a navigation
surface must not cross. It answers "what exists, what does it change, and what
does it require before changing it" for a user who has the catalog installed.

The contract is portable. It defines inventory semantics and a read-only
boundary, not a target project's architecture, commands, or invocation syntax.
Platform invocation belongs to the adapter that owns it.

## The inventory is derived, never stored

<!-- bin/check anchor: "derived from the installed tree at the moment it is asked" is a load-bearing phrase matched by bin/check. Do not reword without updating the corresponding grep assertion in bin/check. -->

An inventory is derived from the installed tree at the moment it is asked. No
list of agent or skill names is written into a contract, a skill, an adapter, or
any committed file.

A stored list is the worst artifact this catalog could carry: it goes stale the
day a surface is added, and unlike a versioned stub it has no marker anyone can
diff. It would not be wrong — it would be quietly wrong, which is the failure
this catalog is shaped to avoid.

The tree is therefore the only source of the set. A surface named in no file but
its own must still appear.

## What a description may claim

<!-- bin/check anchor: "read from declared frontmatter, never inferred from prose" is a load-bearing phrase matched by bin/check. Do not reword without updating the corresponding grep assertion in bin/check. -->

A surface's `visibility`, `effects` and `gates` are read from declared
frontmatter, never inferred from prose. The vocabulary and its rules belong to
`core/surface-metadata/references/surface-metadata-contract.md`; this contract
consumes them and does not restate them.

That boundary is a safety property, not tidiness. Summarising a surface's text
to decide whether it publishes would mean a navigation surface asserting, from a
paraphrase, when this catalog acts on a user's behalf. A description that is
subtly wrong about a publication gate leaves the user with a false model of the
catalog's authority, which is worse than no description at all.

A surface declaring `publishes` is described as publishing, and its gate is
named. The declaration is reported as it stands; it is never softened, omitted,
or explained away.

Execution order inside a surface, its conditional branches, and the internal
skills it calls are not declared anywhere and are therefore not claimed. A
description names what a surface reaches and points at its file.

## Public and internal

`visibility: public` is a documented entry point a user invokes directly.
`visibility: internal` is a lifecycle step another surface orchestrates. Both
appear in an inventory, and the distinction is stated rather than implied by
ordering or omission: a user who cannot see the internal steps cannot understand
what a public entry point will do.

## Read-only boundary

<!-- bin/check anchor: "names invocations and never performs them" is a load-bearing phrase matched by bin/check. Do not reword without updating the corresponding grep assertion in bin/check. -->

A navigation surface names invocations and never performs them. It writes
nothing, calls no network, mutates no repository, and does not invoke any
surface it describes.

This is what keeps navigation from becoming a second dispatch path. A surface
that could launch what it describes would reach every publishing operation in
the catalog while carrying none of the authorization each one requires.

Reading is bounded to the installed plugin root and to frontmatter. Surface
bodies are not read for description, and nothing outside the plugin root is
traversed — a navigation surface describes the catalog, not the user's project.

## Recommending

A recommendation states which capability fits a described situation and why,
drawing only on the lifecycle sequence contract and on what the caller has
stated. It never inspects the target project to form one: reading branches,
pull requests, or working state to decide what a user should run next is a
different capability with a different boundary.

A recommendation names an invocation. It does not perform it.

## Scope of one description

One surface is described per request. Reading every surface to describe one is a
cost paid by the caller with no matching benefit.
