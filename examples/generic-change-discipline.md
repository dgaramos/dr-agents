# Generic change-discipline example

This example shows how a workflow applies
`core/issue-workflow/references/change-discipline-contract.md` while
implementing an issue and while fixing an accepted review finding. It uses a
fictional repository and no project-specific command, credential, or vendor
assumption.

## The request

An issue asks for one behavior change: the paginated list endpoint must stop
requesting further pages once the server stops returning a cursor.

While making that change the workflow notices three other things in the same
files: a helper that is never called, a misspelled comment two functions above
the edit, and a broader opportunity to replace the hand-rolled pagination with
a shared utility.

## What the contract decides

None of the three enters the diff.

- The uncalled helper is **pre-existing dead code**. This change did not orphan
  it, so this change does not remove it.
- The misspelled comment is **adjacent**. The request does not reach that line.
- The shared utility is an **abstraction the request did not ask for**, and it
  would have exactly one caller today.

The cursor check itself is written inline rather than behind a new
`PaginationPolicy` object, because a single-use abstraction is inlined at its
caller.

## Implementation output

The items are named, with their locations, in the implementation block:

```md
## Implementation — acme/widgets#128

**Branch:** `128-fix/pagination-cursor`
**Commits:** 2
**Quality command:** passed
**Test-first evidence:** Red `test_stops_without_cursor` failed on the missing cursor guard; Green added the guard; refactor none
**Spec task traceability:** unavailable: trio lacks traceability format
**Acceptance criteria:** all addressed
**Contribution guidance:** applied: Conventional Commits, run the test suite before pushing
**Observed, not changed:** unused `legacy_page_token` helper at `api/pagination.py:12`; misspelled comment at `api/pagination.py:31`; pagination could move to the shared client utility
**Next:** ship-issue
```

A run that notices nothing outside its scope emits `**Observed, not changed:**
none`. That is the common case, not a gap in the report.

## The same line in a findings fix

A reviewer later accepts one finding: the cursor guard reads the wrong key. The
minimal correction changes that key and nothing else — in particular it does
not take the opportunity to finally delete the dead helper sitting three lines
above it.

```md
## Findings handled — generic reviewer

**PR/ref:** acme/widgets#131
**Head verified:** `a1b2c3d`
**Pertinent, in scope:** 1 · **Separate issue:** 0 · **Not pertinent:** 0 · **Unverifiable:** 0
**Validation:** passed
**Decisions:** #1 fix in this PR
**Commits:** #1 → `a1b2c3d`
**Issues:** none
**Replies prepared:** 1 · **Published:** not requested
**Publication identity:** none
**Observed, not changed:** unused `legacy_page_token` helper at `api/pagination.py:12`
```

## When the plan says otherwise

If the approved plan had explicitly called for the shared pagination utility,
the plan would win. The workflow builds the utility as approved and records the
tension under `Observed, not changed:` — it does not reopen the approval gate
to argue the contract, and it does not quietly deliver less than was approved.

## The reviewer's side

A hunk that none of the above explains is a `Change discipline` finding with
`file:line` evidence, classed `nit` by default and `important` only when the
untraceable hunk alters behavior. A reviewer who simply prefers a different
name has no finding at all: style preference is excluded here as it is
everywhere else.
