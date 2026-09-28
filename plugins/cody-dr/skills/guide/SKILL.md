---
name: guide
description: Cody DR explains what this catalog offers, what each surface changes, and how the capabilities compose, without invoking any of them.
visibility: public
effects: [read-only]
gates: [none]
---

# Cody DR guide

Load `core/workflow-navigation/references/navigation-contract.md` before
answering. It defines what an inventory contains, what a description may claim,
and the read-only boundary. Load
`core/workflow-navigation/references/lifecycle-sequence-contract.md` for how
the capabilities compose and which stages are optional.

Resolve the installed plugin root from `${CODEX_PLUGIN_ROOT}`. If it is unset, resolve it
relative to this skill as `<this skill's directory>/../..`. Derive the
inventory from `<root>/skills/*/SKILL.md` and `<root>/agents/*.md` at the
moment the question is asked. Read frontmatter only, and read nothing outside
that root.

Report each surface's `visibility`, `effects` and `gates` exactly as
declared. A surface declaring `publishes` is reported as publishing, with its
gate named.

Invocation on this platform is `$<skill>` for a skill and the agent's own name for
an agent. Name the invocation; never perform it, and never invoke a surface
being described.

On the Claude Code side, `claude plugin details <plugin>` reports component
counts and projected token cost. Point at it rather than reproducing it; it is
platform state, not catalog content.

Describe one surface per request when asked to go deep. Identity in the output
is **Cody DR**.
