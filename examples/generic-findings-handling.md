# Generic findings-handling example

Input: `handle the findings from review #42`

The handler loads `core/findings-handling/references/findings-contract.md` and
the target profile, then verifies each finding against the current head before
acting.

## Example triage

**Finding A** — `API & compatibility · 🟠 Major` at `api/handler.py:48`

The condition exists on the current head. The fix (retaining `next_page`) is
within the PR's scope and minimal. Classification: `fix now`.

1. The handler makes the minimal correction.
2. Runs the profile's quality command (`bin/check`). It passes.
3. Commits the fix in isolation.
4. Prepares reply: "Retained `next_page` in the response; `bin/check` passes."

**Finding B** — `Architecture & maintainability · 🟡 Minor` at `[general]`

The finding is valid but requires touching files outside this PR's scope.
Classification: `defer`.

The handler produces a publication-ready issue draft using the issue-authoring
contract. The draft's context references the original finding and its evidence
location. No code change is made.

**Finding C** — `Behavior & reliability · 🔴 Critical` at `src/retry.py:12`

The described condition is gone on the current head — a prior commit already
addressed it. Classification: `reject`.

Reply text: "The condition described no longer exists on the current head at
`src/retry.py:12`; the finding is superseded."

## Publisher-first outcome

For an explicitly authorized reply or resolution, the handler first uses the
configured reviewer App and verifies its actor and target thread. If that
operation is unavailable before dispatch, an explicitly authorized authenticated
personal account may publish instead; the result names that account as a
personal fallback. An ambiguous App dispatch or actor verification failure
requires inspection before retrying. A proven token-generation failure before
any mutation permits fallback; a generic error does not.

## Outcome summary (not published)

```md
## Findings handled — Claudio DR

**PR/ref:** PR #42
**Head verified:** `a1b2c3d`
**Fix now:** 1 · **Defer:** 1 · **Reject:** 1 · **Superseded:** 0
**Validation:** passed
**Replies prepared:** 3 · **Published:** not requested
**Publication identity:** none
```

Both Claudio DR and Cody DR produce equivalent triage, fix, and deferral
behavior from the same findings; they differ only in reviewer identity and
platform publisher mechanics.
