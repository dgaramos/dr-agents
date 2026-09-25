---
name: design-and-author
description: Claudio DR chains design discovery directly into issue authoring, passing the Design Brief as author-issue context without a separate manual invocation.
visibility: public
effects: [publishes]
gates: [explicit-authorization]
---

# Claudio DR design-and-author

Discover the target profile first with
`core/profile-discovery/references/profile-discovery-contract.md`.

Load `core/design-discovery/skills/design-and-author/SKILL.md` and follow its
referenced contracts. Use Claudio DR identity in the result. Do not publish,
create issues, comments, uploads, or code changes unless the caller separately
authorizes that exact action.
