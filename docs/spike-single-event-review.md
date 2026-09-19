# Spike: does a GraphQL pending-review reply flow eliminate review shells?

**Answer: yes.** A thread reply attached to a pending review and submitted with
it produces exactly one substantive review event and no empty shell. The REST
reply route produces one empty `COMMENTED` shell per reply.

Issue: dr-agents#326. Measured 2026-09-19 on throwaway PR dr-agents#378 at
head `a660b11dead43bc327b0649ae9f0c4af2b43c208`.

## Method

A seed review created one inline thread. The same reply was then made twice, by
each route, and the PR's review list was read after each step.

- **Route A — REST:** `POST /pulls/:n/comments/:id/replies`
- **Route B — GraphQL, three mutations:** `addPullRequestReview` (pending, no
  event) → `addPullRequestReviewThreadReply(pullRequestReviewId,
  pullRequestReviewThreadId)` → `submitPullRequestReview(event: COMMENT)`

## Raw observations

Review events after each step, in order:

| Step | Event id | State | Body length | `commit_id` |
| --- | --- | --- | --- | --- |
| seed review | `5254209349` | `COMMENTED` | 59 | `a660b11` |
| after Route A reply | `5254209714` | `COMMENTED` | **0** | `a660b11` |
| Route B pending (before submit) | `5254210263` | `PENDING` | 0 | — |
| after Route B submit | `5254210263` | `COMMENTED` | 59 | `a660b11` |

Route A added one event. Route B added one event. The difference is what those
events are: Route A's is an empty shell, Route B's is the substantive review.

Comment placement — both replies landed in the same thread
(`PRRT_kwDOT-4AwM6j8bGs`):

| Comment | Owning review | Route |
| --- | --- | --- |
| `4051972212` | `5254209349` | seed |
| `4051972595` | `5254209714` (body-less) | A |
| `4051973033` | `5254210263` (substantive) | B |

## Why it works

A review comment always belongs to a review. The routes differ only in which
review that is. REST has no pending review to attach the reply to, so the API
creates one implicitly and submits it empty — the shell is not a side effect to
be suppressed, it is the container the reply required. GraphQL lets the caller
name an existing pending review, so the reply joins the review already being
submitted and no second container is needed.

This also explains the `commit_id` drift seen earlier: each implicit shell is
created at whatever head is current when the reply is posted, which is why a
prior-head lookup that trusts the newest event can select a shell's SHA.

## Conclusion

Positive. Batching replies inside a single review submission is achievable
through the documented GraphQL mutations, with no change to the reply's thread
placement.

Consequences for the catalog:

- The reply route in `core/pr-review/references/review-contract.md` can state
  the no-shell route as the rule rather than declaring the REST limitation.
- The tolerance rule from dr-agents#319 can stop being the default for the
  GraphQL route; shells remain expected only where REST is the only option.
- Epic dr-agents#315 `AC-02` — exactly one substantive review event per pass —
  becomes reachable. It is currently shipped in its weaker "state the
  limitation" form via dr-agents#341.

## Limitations

- Measured with the maintainer's personal token, not a GitHub App installation
  token. Review-event creation semantics are a property of the API rather than
  the identity, and both routes were exercised under the same token, so the
  comparison holds; running it as the App is still the honest confirmation
  before the publisher changes.
- One PR, one thread, one reply per route. Not measured: several replies inside
  one pending review, a reply combined with new inline findings in the same
  submission, or a reply to a thread opened by a different author.
- No change was made to `.github/scripts/publish-review.sh` or the reusable
  workflow, per the spike's scope.
