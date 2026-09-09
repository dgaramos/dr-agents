# Portable review contract

Collect the explicit PR/ref, base, current head, changed files, relevant issue,
checks, and existing review discussion. Load the target project's profile before
evaluating the diff. A missing profile means review only generic correctness,
security, compatibility, and evidence; state that limitation in the summary.

Read changed code with its callers, tests, and public contract. Do not treat a
diff in isolation as proof of behavior. For local work, report which staged,
unstaged, and untracked changes were in scope. Do not attribute unrelated files
to the requested review.

## Evidence and findings

Formal findings require current `file:line` evidence, a reproducible flow or
fact, concrete impact, and confidence `>= 80/100`. Put lower-confidence
hypotheses only in the summary as limitations or observations. Do not use style
preference as a finding. A `nit` never justifies requesting changes.

Before creating a finding, load every current review thread and top-level review
comment. Treat a thread as the same finding when its current evidence describes
the same failing behavior or correction, even if it was authored by a human or
another review bot. For an open matching thread, do not create a new inline
comment: verify it against the current head and add a factual reply to that
thread instead. Open a new thread only for a materially distinct cause, impact,
or evidence location. A resolved matching thread stays historical; reply there
only when the current head proves the issue regressed, and state that it needs
human reopening if the platform cannot reopen it.

Choose one category and one class:

| Category | Examples |
| --- | --- |
| Security & authorization | validation, sessions, credentials |
| Data integrity & recovery | persistence, migration, backup |
| API & compatibility | public interface or protocol |
| Behavior & reliability | flow, failure, idempotency |
| Architecture & maintainability | concrete boundary risk |
| Tests & observability | missing behavioral evidence |
| Documentation & contribution | incorrect public instruction |
| Performance & capacity | measurable scale or resource risk |

| Class | Badge | Meaning |
| --- | --- | --- |
| blocking | 🔴 Critical | material security, data, contract, or failure risk; requests change |
| important | 🟠 Major | probable regression or incompatibility; requests change |
| nit | 🟡 Minor | concrete non-blocking improvement; never requests change |

```md
<category> · <badge> · <⚡ Quick win|🔧 Focused change|🧩 Follow-up>

**<short imperative title>**

<objective explanation of the failing flow or condition.>

**Evidence:** `<file:line>` — <verified fact>; confidence: <N>/100.
**Impact:** <concrete consequence>.
**Suggested fix:** <smallest credible correction>.
```

Inline findings require a changed line. General findings use `[general]` as the
location and go in the review body.

## Re-review

When reviewing a PR again after changes, load all current threads, top-level
comments, reviews, and their states. Locate the last head reviewed by the same
reviewer.

1. If the prior SHA is trustworthy and ancestral to the current head, inspect
   only the diff from prior head to current head for new findings.
2. Otherwise, declare the delta unverifiable and review the full current
   base-to-head comparison.
3. Classify every previous finding as `resolved`, `fixed but thread open`,
   `unresolved`, `superseded`, or `unverifiable`. Thread replies are context,
   not proof. Do not repeat resolved findings.

For every prior thread, record the current-head evidence and choose exactly one
action: `reply and resolve`, `reply but keep open`, `leave open`, or `defer`.
Never thank or resolve a thread merely because its author says it was fixed.

Use the re-review preamble in the summary section below before the
new-findings section.

## Publication boundary

Prepare a review body and inline comments only after verifying the current head.
Publish, reply, resolve threads, approve, or request changes only when the user
explicitly asks. Apply `publication-routing-contract.md` to select the App or
authenticated personal fallback. Never look
for credentials in the target repository.

Without either usable route, return the formatted content as `not published`.

For authorized agent publication, use `COMMENT` for every finding class. An
agent review may identify a blocking or important risk, but it must not submit
`REQUEST_CHANGES`; merge blocking remains a human decision. Use `APPROVE` only
with no findings and only when the target profile explicitly authorizes agent
approval.

Submit **one single PR review** through a publication manifest that bundles all
findings and thread actions together:

- Findings whose evidence line is in the diff → inline comments in the review's
  `comments` array, each at the exact `path` and `line` (or `position`) from
  the evidence. Do not open a separate review per finding.
- Findings whose evidence line is outside the diff or marked `[general]` →
  included in the review body, not as standalone pull request comments.
- The review body also contains the summary block.

Never submit multiple review events for the same pass. Never post findings as
standalone pull request comments outside a review submission.

The manifest contains `review_body`, `inline_comments`, `replies`, and
`resolve_thread_ids`. `inline_comments` is an array of `{path, line, body}`:
every formal finding on a changed line gets its own entry. A publisher that
cannot submit that array must return the manifest as `not published`; it must
never collapse those findings into one general comment. `replies` and
`resolve_thread_ids` are validated against the supplied PR before publication.
The publisher transports this manifest unchanged. The reviewer owns the review
summary and must not delegate its factual analysis to the publisher.

`replies` also carries duplicate findings: it references the existing top-level
review-comment identifier and adds the current-head evidence, rather than
creating a competing thread. The summary reports new inline findings and
thread updates separately.

After publishing, verify the resulting review's author and event match the
expected reviewer identity. After replying to a thread, verify the reply is
authored by the expected reviewer in the intended thread. After resolving a
thread, verify the App resolved the intended thread.

## Summary

Emit one summary block per review:

````md
## Review — <reviewer name>

**Scope:** <PR/ref>, `<base>` → `<head>`
**Reviewed head:** `<sha>`
**Profile:** <profile name or none>
**Checks:** <consulted results>; not run: <reason or none>
**Findings:** 🔴 Critical: N · 🟠 Major: N · 🟡 Minor: N
**Thread updates:** `<N replies to existing findings; or none>`
**Risk axes:** <evaluated>; not applicable: <axes>
**Verdict:** `<approve|request changes|comment|no findings>`
**Publication:** `<not requested|not published|published by <reviewer name>>`

## Walkthrough

| Area / files | What changed | Why it matters |
| --- | --- | --- |
| `<area or path>` | `<factual behavior change>` | `<observable consequence>` |

Omit this section for a small, single-purpose change that the opening summary
already explains. Keep it when the PR crosses modules, layers, or contracts.

## Behavior map

Include a small Mermaid flow or sequence diagram only when it makes a changed
interaction, state transition, or data flow easier to understand. Every node
and edge must be supported by the reviewed diff or its verified callers. Omit
this section when a diagram would merely repeat prose.

## Merge risk

**Risk:** `<minimal|low|moderate|high>` — `<evidence-based reason>`.

## Pre-merge checks

| Check | Status | Evidence / limitation |
| --- | --- | --- |
| `<test, build, migration, or review condition>` | `<passed|failed|not run>` | `<actual result or reason>` |

Do not invent checks, estimates, risk, or warnings. A concern belongs here only
when current evidence supports it; otherwise state the applicable limitation.

```mermaid
flowchart LR
  Input[Changed input] --> Service[Changed behavior]
  Service --> Result[Observed result]
```
````

With no findings, keep the zero counts and state actual review limitations.

## Re-review preamble

```md
## Re-review — <PR/ref>

**Previous reviewed head:** `<sha or unavailable>`
**Current head:** `<sha>`
**Delta:** <prior head → current head, or full comparison and reason>
**Previous findings:** resolved: N · fixed but thread open: N · unresolved: N · superseded: N · unverifiable: N
**Discussion checked:** <threads and general comments consulted>

| Previous finding | Current-head evidence | Decision |
| --- | --- | --- |
| `<thread or finding>` | `<verified fact>` | `<reply and resolve|reply but keep open|leave open|defer>` |
```
