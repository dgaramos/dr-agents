# Spec-Driven Development contract

## Purpose

Spec-Driven Development (SDD) turns a feature request into a portable,
machine-readable trio of documents before issue authoring or implementation.
The trio consists of `requirements.md`, `design.md`, and `tasks.md`. A spec
agent must create the documents in that order and keep their terminology and
acceptance criteria aligned.

The contract is portable. It defines document structure and workflow behavior,
not a target project's architecture, commands, credentials, issue metadata, or
deployment policy.

When a profile declares an external spec source, it must use the exact
`## Spec source` convention from the profile-discovery contract. The declaration
authorizes resolving only its exact trio path; a missing, partial, ambiguous, or
inaccessible declaration never authorizes inference of an alternate source.

The portable spec-authoring entrypoint is `core/spec/SKILL.md`. Adapter
bindings are deliberately deferred to their dedicated follow-up issues.

## Target

Resolve the target through
`core/target-resolution/references/target-resolution-contract.md` before
loading a profile or running any repository-dependent command. Drafting a trio
needs no target; writing one does, and the target of a write is the specs
repository, never the repository the agent happens to be invoked from.

For an authorized spec write, resolve it from the caller's specs repository:

```text
core/target-resolution/scripts/resolve-target.sh \
  --from-specs-repository "$SPECS_REPOSITORY"
```

The result declares `source: specs-repository`. Discover the profile at that
target with `discover-project-profile.sh --root <checkout>`; never apply the
current directory's profile to the specs repository.

## `requirements.md`

`requirements.md` must contain these headings in this order:

1. `## Objetivo` — the user or system outcome.
2. `## Requisitos funcionais` — observable capabilities and rules.
3. `## Requisitos não-funcionais` — applicable quality, security,
   accessibility, performance, compatibility, and operational constraints.
4. `## Critérios de aceite` — independently verifiable criteria in
   Given/When/Then form. Every criterion must state the expected failure state
   when the relevant condition fails. Prefix every criterion with a unique,
   stable identifier in the form `[AC-01]`; preserve that identifier whenever
   the criterion is cited by a task, issue, or execution report.
5. `## Condições de falha` — failure modes, user-visible behavior, recovery,
   and any escalation path.
6. `## Boundaries` — a table using `✅`, `⚠️`, and `🚫` to distinguish included,
   uncertain, and excluded scope.

Do not invent facts that are absent from the request or loaded profile. Record
assumptions and unknowns in the relevant requirement or boundary row.

## `design.md`

`design.md` must contain these headings in this order:

1. `## Stack` — relevant technologies and constraints, or an explicit
   statement that they are unknown.
2. `## Arquitetura` — a Mermaid diagram plus a concise description of
   component responsibilities and data/control flow.
3. `## Contratos de componente` — component inputs, outputs, invariants,
   errors, and ownership boundaries.
4. `## Estratégia de teste` — coverage needed for the acceptance criteria,
   including failure paths and the strongest available validation for
   non-executable work.

The design must trace each significant component decision to a requirement or
constraint. It must not add implementation scope that the requirements exclude.

## `tasks.md`

`tasks.md` must express implementation work as ordered Markdown checkbox tasks.
Each task must name one or more covered acceptance-criterion identifiers from
`requirements.md`, for example `T01 [AC-01]`. Each task must include a nested
`Verification:` sub-item naming the exact command or structural check that
demonstrates completion. Tasks may be grouped under optional `## Checkpoint`
headings; a checkpoint names the decision or approval boundary before later
tasks proceed.

Every acceptance criterion in `requirements.md` must map to one or more tasks,
and every task must be justified by a requirement, constraint, or necessary
validation activity. The task sequence must make dependencies explicit.

How much work one task holds is governed by
`core/work-sizing/references/work-sizing-contract.md`. Coverage rules above
constrain the mapping, not the count: a task naming several criteria is
well-formed, and a boundary between tasks must state what forces it.

## Traceability compatibility

An older trio may lack criterion identifiers or task-to-criterion references.
An agent reading such a trio must state that traceability is unavailable and
must not infer criterion IDs, task coverage, or verification evidence. It may
still use the trio according to the compatibility policy of its consuming
workflow.

## Executor boundary

For an executor, tasks.md is read-only execution input. The executor reads
tasks in order, records each completed task, its declared covered criterion
IDs, and its `Verification:` result, and does not rewrite the spec as part of
implementation. At a
`## Checkpoint`, the executor stops for approval unless the caller explicitly
authorized continuous execution.

## Write boundary

A resolved specs source never ends in an inline-only trio. Three outcomes are
possible, and the summary must state which one applies.

The three conditions are exclusive and exhaustive, and they are selected in
order on two facts only: whether a specs source resolved, and whether the
caller explicitly authorized that exact write.

1. **No resolved specs source.** Whatever the authorization state, return the
   complete trio in the response and report `Write: not written: <reason>`.
2. **Source resolved, no explicit write authorization.** Report
   `Write: proposed path specs/<project>/<slug>/` and, with it, the
   exact write invocation that would perform it. The proposal is a handoff,
   not a write: nothing is created, branched, or published. A slug already
   among the profile's authorized paths proposes that existing path; a slug
   outside them proposes a new one and asks for both the path and the write.
   A resolved source never returns `not written`.
3. **Source resolved and the caller explicitly authorized that exact write.**
   Write the trio, as described below.

An `Authorized path` declaration authorizes reading its exact trio. It does not
by itself authorize a write; the caller's explicit authorization does, and a
proposal for an unauthorized slug asks for both.

## Authorized write

Verify the resolved checkout before any mutation with
`git -C <checkout> status --porcelain` and
`git -C <checkout> rev-parse --abbrev-ref HEAD`. A dirty working tree or an
unexpected branch means the checkout holds work this flow did not produce:
report the observed state in the `Checkout state:` field and stop with a
handoff. Do not stash, reset, check out, or commit around it. This gate applies
to a spec write reached through any entrypoint, including a standalone
invocation of the spec flow.

In `checkout` mode, run every git command inside the resolved checkout —
`git -C <checkout> checkout -b feat/<slug>`, `git -C <checkout> add`,
`git -C <checkout> commit`, `git -C <checkout> push`. Write
`specs/<project>/<slug>/requirements.md`, `design.md`, and `tasks.md`, and
register the slug in the project's `index.md` in the same commit.

In `mode: remote-only` there is no checkout to write in. Create the branch and
its files with

```text
core/target-resolution/scripts/remote-write.sh <target> <base-branch> \
  feat/<slug> <manifest> <message-file>
```

whose manifest carries the three trio files and the updated `index.md`. Never
run git in the current directory on the specs repository's behalf.

Open the pull request through the adapter's `ship-change` flow, which owns
publisher selection, dispatch, and verification. Do not open it with an ad-hoc
command. In `mode: remote-only` hand `ship-change` its remote-only entry point
— target, head branch `feat/<slug>`, and base branch, with no checkout — as
`core/issue-workflow/references/ship-change-contract.md` defines it; the
branch `remote-write.sh` already pushed is published, never rebuilt in a
reconstructed checkout. Select the publisher against the resolved target and qualify the
dispatch with it — `--repo <target>` or an equivalent repository-qualified API
call. Selecting the publisher at the target and then dispatching unqualified
runs it against the current directory's repository: that is a failed
publication, not a recoverable detail.

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

## Publication boundary

Drafting a spec does not authorize creating an issue, publishing artifacts,
changing code, or opening a pull request. A spec is written outside the current
response only when the caller explicitly authorizes that exact write and the
loaded profile declares the target path; without that authorization the agent
proposes the path and stops.

**Publication:** not published unless that explicit write authorization and profile-declared target are present.
