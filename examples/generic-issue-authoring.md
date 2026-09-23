# Generic issue authoring example

With a profile-declared, authorized spec location, authoring may use the trio
as context and add `Spec: <location>`; without it, no spec source is inferred.

Input: `draft an issue for the missing pagination contract in acme/widgets`

The author first resolves the target through
`core/target-resolution/references/target-resolution-contract.md`. The
`owner/repository` reference names `acme/widgets`, so the profile is discovered
at that repository's resolved checkout — never at the current directory. With no
checkout available the mode is `remote-only`: the issue template is read with
`gh api repos/acme/widgets/contents/.github/ISSUE_TEMPLATE/...`, no git command
runs in the current directory on the target's behalf, and the summary declares
`Profile: none (remote-only)`.

The author loads `core/issue-authoring/references/issue-contract.md` and the
resolved target's profile before drafting. It produces a complete draft immediately —
without asking questions — unless a material decision cannot be inferred.

Example draft body:

```md
## Context

The pagination response contract is not documented, so consumers implement
conflicting assumptions about when iteration ends.

## What to do

- Define the pagination fields and their semantics in the API contract.
- Add a behavioral test that fails when a paginated response omits a required
  field.
- Update the consumer guide with the canonical pagination example.

## Expected result

Every consumer reads the same contract and the behavioral test enforces it on
every change.

## Acceptance criteria

- [ ] Given a paginated response, when the contract is read, then `next_page`
  presence and absence are unambiguously defined.
- [ ] Given a response that omits `next_page`, when the behavioral test runs,
  then it fails.
- [ ] Given the consumer guide, when a new consumer follows it, then it
  iterates correctly without reading the implementation.
```

Without publisher authorization, the draft is returned as `not published` with
the summary:

```md
## Issue draft — Claudio DR

**Target:** acme/widgets (remote-only)
**Title:** Define the pagination response contract
**Profile:** none (remote-only)
**Profile-owned fields:** unknown: profile not loaded
**Publication:** not requested
```

With publisher authorization and a profile that documents `create-issue` mode,
the `create-issue` publisher is selected against the resolved target with
`select-publisher.sh acme/widgets <workflow>`, and the dispatch is qualified
with `--repo acme/widgets` so it cannot run in the current directory's
repository. The issue is created as the configured reviewer bot (Claudio DR or
Cody DR) and the summary records the resulting issue number. The created
issue's repository is then verified to be the resolved target; an issue created
anywhere else is a failed publication regardless of its content.

The example contains no labels, assignee, milestone, or credential assumption.
Both Claudio DR and Cody DR produce equivalent draft structure from the same
input; they differ only in author identity and platform publisher mechanics.
