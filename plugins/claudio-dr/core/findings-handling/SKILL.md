---
name: handle-findings
description: Triage, fix, defer, or reject review findings against the current head. Produces minimal in-scope fixes, defers out-of-scope work as draft issues, and prepares replies and thread-resolution text without publishing unless explicitly authorized.
---

<!-- generated from core/findings-handling/SKILL.md by bin/sync-plugin-core-bundles.sh -- do not edit -->

# Portable findings handling

Load [findings-contract](references/findings-contract.md) before acting on any
finding. It defines current-head verification, triage classifications, fix
requirements, out-of-scope deferral via the issue-authoring contract, reply and
resolution behavior, and the outcome summary format.

Load the target project's profile to obtain the quality command and publisher
configuration. A missing profile means no quality command is available; state
that limitation in the outcome summary and ask the user which validation to run
before claiming resolution.

Do not publish replies, resolve threads, push, or merge unless the user
explicitly authorizes it.
