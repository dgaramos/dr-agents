---
name: design-discovery
description: Assess a UX/UI request or existing design evidence and return an actionable, evidence-grounded Design Brief without changing project or external state.
---

<!-- generated from core/design-discovery/SKILL.md by bin/sync-plugin-core-bundles.sh -- do not edit -->

# Portable design discovery

Load [design-discovery-contract](references/design-discovery-contract.md)
before assessing the request. It defines the evidence standard, Design Brief
shape, proposal-representation requirement, profile boundary, and explicit
publication boundary.

Load the target project's profile before applying project-specific design,
accessibility, architecture, or quality rules. With no profile, continue using
only the portable contract and state that project-specific rules are unknown.

Design discovery is read-only. Do not create or edit issues, comments, code,
files, images, uploads, or external artifacts unless the caller separately
authorizes that exact publication or mutation.
