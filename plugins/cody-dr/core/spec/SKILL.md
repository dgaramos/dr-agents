---
name: spec
description: Turn a request into a portable Spec-Driven Development trio—requirements, design, and ordered implementation tasks—without writing or publishing by default.
---

# Portable spec authoring

Load [spec-contract](references/spec-contract.md) before drafting. It defines
the mandatory structure of `requirements.md`, `design.md`, and `tasks.md`, the
executor boundary, and the explicit write and publication boundary.

Resolve the target through
`core/target-resolution/references/target-resolution-contract.md` before
loading a profile. An authorized spec write targets the specs repository:
resolve it with
`core/target-resolution/scripts/resolve-target.sh --from-specs-repository
"$SPECS_REPOSITORY"`, which reports `source: specs-repository`.

Load the profile discovered at that target before applying project-specific
architecture, commands, repository locations, or delivery rules. With no
profile, create a portable response only and state that project-specific
settings are unknown. Never apply the current directory's profile to another
repository.

## Steps

1. Detect whether the caller supplied a Design Brief. It is optional context:
   preserve its evidence, constraints, assumptions, open questions, and success
   criteria without treating it as an authorization to write or publish.
2. Classify the request as `feature`, `chore`, `spike`, or `bug`. State the
   classification and investigate the available request and repository evidence
   enough to avoid inventing requirements.
3. Draft the trio in order: `requirements.md`, then `design.md`, then
   `tasks.md`. Follow every required heading and boundary from the spec
   contract. Keep requirement, design, and task terminology consistent.
4. Validate the draft before returning it:
   - every acceptance criterion maps to at least one task;
   - every task names a `Verification:` command or structural validation;
   - task order exposes dependencies and any `## Checkpoint` approval boundary;
   - design decisions are supported by requirements, constraints, or disclosed
     assumptions.
5. When an issue body already contains a `Spec:` reference, use the
   profile-declared exact source only after it passes the authorized-source
   conditions. Report the three resolved files in the handoff; do not infer an
   alternate location or alter the issue body.
6. Decide the write outcome per the contract's write boundary:
   The three branches are exclusive and exhaustive; select on whether a source
   resolved and whether the exact write was explicitly authorized.
   - No resolved specs source: return the trio in
     the response and report `Write: not written: <reason>`.
   - Source resolved and no explicit write authorization: report
     `Write: proposed path specs/<project>/<slug>/` together with the exact
     write invocation that would perform it. Propose; do not write.
     A resolved source never returns `not written`.
   - Source resolved and the caller explicitly authorized that exact write:
     verify the checkout before any mutation, then write the trio on branch
     `feat/<slug>` with `git -C <checkout>`, or with
     `core/target-resolution/scripts/remote-write.sh` in `mode: remote-only`.
     Register the slug in the project's `index.md` and open the pull request
     through the adapter's `ship-change` flow, dispatched `--repo <target>`.
7. Emit the summary block below.

## Spec summary

```md
## Spec — <request reference>

**Target:** owner/repository (checkout: /absolute/path)
**Profile:** project (/absolute/path/.dr-agents/project/PROFILE.md)
**Classification:** <feature|chore|spike|bug>
**Design Brief:** <used|not supplied>
**Trio:** `requirements.md`, `design.md`, `tasks.md`
**Traceability:** <every AC mapped to a task; every task has Verification:|limitations>
**Checkout state:** <not applicable|clean on <branch>|<observed state>>
**Write:** <not requested|not written: reason|proposed path specs/<project>/<slug>/|written to <path>>
**Issue links:** <not applicable|not added: reason|added to #N>
**Publication:** not published
```

The spec skill never creates an issue, modifies code, writes a repository, or
publishes an artifact by default. It writes only under an explicit
authorization for that exact write, and only inside the resolved target —
`git -C <checkout>` or `remote-write.sh`, never a bare git command in the
current directory.
