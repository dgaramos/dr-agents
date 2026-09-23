# Generic issue-to-change lifecycle

This example shows the portable `execute-issue` lifecycle for issue `#42` in
the neutral `acme/widgets` repository. It uses only illustrative values: a
real project profile supplies its branch convention, quality command, PR
metadata, and publisher details.

## Single human gate

An explicit `execute-issue` request authorizes the full lifecycle. The only
human gate is after `plan-issue` surfaces the plan: the caller reviews it and
approves before any file is touched. After that single approval, `start-issue`,
`plan-implementation`, `implement-issue`, and `ship-issue` all proceed without
further confirmation. `ship-issue` does not require an extra approval gate when
reached within an `execute-issue` run — that gate only applies when
`ship-issue` is invoked standalone.

```md
## Plan — #42
[plan content]

Next: start-issue (awaiting explicit approval)
```

After the caller approves:

```md
[start-issue → plan-implementation → implement-issue → ship-issue → PR opened]
No further confirmation requested.
```

## 1. Start the explicit issue

The caller explicitly asks to execute `#42`. `start-issue` resolves the target
repository first, discovers the one profile at that target's checkout, reads
the issue, and checks its declared dependencies. It then verifies the checkout
is clean and on the base branch before creating anything, and runs every git
command as `git -C /src/widgets`.

```md
## Start — #42

**Target:** acme/widgets (checkout: /src/widgets)
**Profile:** widgets (/src/widgets/.dr-agents/widgets/PROFILE.md)
**Issue:** Document widget cache invalidation
**Branch:** `42-docs/widget-cache-invalidation` from `main`
**Checkout state:** clean on `main`
**Dependencies:** all resolved
**Next:** plan-implementation
```

A checkout holding unrelated work is not a checkout this lifecycle may commit
into. It stops before the branch exists rather than building on someone else's
state:

```md
## Handoff — start-issue

**Stopped at:** /src/widgets is dirty: `src/cache.c`, `docs/cache.md`
**Last verified head:** `a1b2c3d`
**Next step:** commit, stash, or discard the unrelated changes, then resume
```

If dependency `#41` is still open, the lifecycle stops here instead of
guessing or creating a speculative change:

```md
## Handoff — start-issue

**Stopped at:** unresolved dependency #41
**Last verified head:** `a1b2c3d`
**Next step:** complete or explicitly waive dependency #41
```

## 2. Implement and validate one logical unit at a time

Before implementation, `plan-implementation` prints a read-only test-first
plan that maps every executable criterion to Red → Green → Refactor coverage,
or records the strongest structural validation when TDD is not applicable.
`implement-issue` then addresses the acceptance criteria on the created branch.
After each logical change it runs the profile-owned command, for example
`make check`. A passing unit can be committed; the implementation phase never
pushes or opens a pull request.

```md
## Implementation — #42

**Branch:** `42-docs/widget-cache-invalidation`
**Commits:** 2
**Quality command:** passed
**Acceptance criteria:** all addressed
**Next:** ship-issue
```

A failing quality gate is a terminal handoff for this execution. Later phases
do not run until the failure is fixed and validated:

```md
## Handoff — implement-issue

**Stopped at:** `make check` failed after commit 2: broken documentation link
**Last verified head:** `d4e5f6a`
**Next step:** fix the failing check, rerun `make check`, then resume
```

## 3. Ship the completed change

For an approved `execute-issue` lifecycle, the normal delivery path is already
authorized: commit, push, and opening a fully populated PR. `ship-issue` runs
the final quality gate, derives the title and body from the issue, and uses the
profile values rather than hardcoding them in the portable workflow.
When the profile supplies a PR template, the body retains every template
heading and fills each section with a change-specific answer or `Not
applicable`.

The pull request is opened in the resolved target, not in whatever directory
the agent started in. `ship-issue` selects the target's `create-pr` publisher
with `select-publisher.sh acme/widgets
.github/workflows/publish-<agent>-pr.yml`, dispatches it qualified with
`--repo acme/widgets`, and then verifies that the PR that came back belongs to
`acme/widgets`. A PR opened anywhere else is a failed publication, however
correct its content.

```md
## Ship — #42

**Target:** acme/widgets (checkout: /src/widgets)
**Profile:** widgets (/src/widgets/.dr-agents/widgets/PROFILE.md)
**Branch:** `42-docs/widget-cache-invalidation`
**Checkout state:** clean on `42-docs/widget-cache-invalidation`
**Final quality gate:** passed
**PR:** https://github.com/acme/widgets/pull/42
**Metadata applied:** `documentation`, milestone `v1`, assignee `maintainer`,
Project `Widgets` / `In Progress`
**Metadata verified:** base → `main`; labels → present; milestone → `v1`;
assignee → `maintainer`; Project → `In Progress`
```

If a caller invokes `ship-issue` on its own without explicit shipping approval,
it prepares the same PR payload but does not publish it:

```md
## Ship — #42

**Target:** acme/widgets (checkout: /src/widgets)
**Profile:** widgets (/src/widgets/.dr-agents/widgets/PROFILE.md)
**Branch:** `42-docs/widget-cache-invalidation`
**Checkout state:** clean on `42-docs/widget-cache-invalidation`
**Final quality gate:** passed
**PR:** not published
**Metadata applied:** none
**Metadata verified:** none

## Handoff — ship-issue

**Stopped at:** standalone shipping has no explicit approval
**Last verified head:** `d4e5f6a`
**Next step:** explicitly request issue execution or authorize shipping
```

Review publication, replies, and thread resolution are never implied by issue
execution. They require their own explicit authorization and a configured
project publisher.

## 4. Final orchestration summary

When all phases complete, `execute-issue` reports the outcome without hiding
the branch, validation, or PR state:

```md
## Execute — #42

**Phases completed:** start-issue · plan-implementation · implement-issue · ship-issue
**Stopped at:** none
**PR:** https://github.com/acme/widgets/pull/42
```
# Spec-driven execution example

For an authorized, profile-declared `Spec:` location, the executor reads
`tasks.md`, performs tasks in order, and runs only profile-compliant
`Verification:` commands. It stops at `## Checkpoint` unless continuous
execution was explicitly authorized; an unavailable spec produces a handoff.
