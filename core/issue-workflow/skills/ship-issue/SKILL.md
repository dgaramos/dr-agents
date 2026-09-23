---
name: ship-issue
description: Run final validation and formally ship a completed implementation.
---

# Portable ship-issue

Load `../../references/ship-issue-contract.md`. Resolve the target first with
`core/target-resolution/references/target-resolution-contract.md`
and discover its profile there. When reached through an
approved `execute-issue` lifecycle, run the final quality gate, push, open the
PR, apply profile metadata, and emit the `Ship` output block directly. Only
require explicit approval when `ship-issue` is invoked standalone, outside an
`execute-issue` lifecycle.
