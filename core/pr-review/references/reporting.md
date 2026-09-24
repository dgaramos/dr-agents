# Review reporting categories

The finding template, the review summary template, and the re-review preamble
are defined in one place only:
[`review-contract.md`](review-contract.md). This file carries the category and
class vocabulary those templates reference; it must not restate them.

## Finding rules

Only formalize findings with confidence `>= 80/100`. Every formal finding needs
current evidence, a concrete impact, and the smallest credible correction. Do
not fabricate tool output, prompts, metrics, or automated fixes. The confidence
value is a reviewer-internal gate: it is recorded in the publication manifest
and the terminal summary, never rendered into the published finding.

Choose one category:

| Category | Use for |
| --- | --- |
| `Security & authorization` | Credentials, sessions, authorization, validation, or exposure. |
| `Data integrity & recovery` | Persistence, migration, retention, backup, restore, or history. |
| `API & compatibility` | Public interface, contract, protocol, or compatibility. |
| `Behavior & reliability` | Functional flow, failure behavior, idempotency, or concurrency. |
| `Architecture & maintainability` | Dependency boundary or concrete maintenance risk. |
| `Tests & observability` | Missing behavioral evidence or diagnosability. |
| `Documentation & contribution` | Incorrect public instructions or contributor workflow. |
| `Performance & capacity` | Measurable resource, retention, or scale risk. |
| `Change discipline` | Diff hunk not traceable to the request, unrequested abstraction, adjacent cleanup, or orphaned symbol. |

| Class | Badge | Meaning |
| --- | --- | --- |
| `blocking` | `🔴 Critical` | Probable security, data, contract, or material failure; requests change. |
| `important` | `🟠 Major` | Probable regression or incompatibility; requests change. |
| `nit` | `🟡 Minor` | Concrete non-blocking improvement; never requests change. |

Use `⚡ Quick win` for a local change, `🔧 Focused change` for a small
coordinated change, and `🧩 Follow-up` when the correction does not fit the PR.

The category and class tables above are template anchors. They are asserted
against `review-contract.md` by
`core/pr-review/scripts/verify-review-surface.sh`: changing one of them here and
not there, or the reverse, fails the quality gate.

## Existing-thread rule

Search current human and bot review threads before publishing. If an open thread
already describes the same verified defect, append a concise reply with the
current-head evidence instead of creating another inline finding. Do not treat
matching words alone as duplication: the behavior, cause, and affected flow
must match. Report those replies as thread updates in the summary.

A reply is not a review pass. See the reply-route and prior-head rules in
[`review-contract.md`](review-contract.md).
