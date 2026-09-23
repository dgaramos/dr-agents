# Generic Spec-Driven Development example

A request asks for a service to notify a customer when an invoice becomes
overdue. A spec agent can produce this minimal trio without assuming a specific
application stack.

## Design Brief

- **Outcome:** notify a customer once when an unpaid invoice becomes overdue.
- **Constraint:** the host project owns retry policy and provider selection.
- **Open question:** whether retries are enabled; this becomes a checkpoint,
  not an inferred implementation detail.

## Authorized source

The consuming profile declares exactly one accessible source before an agent
resolves the trio:

```md
## Spec source

- **Repository:** `${ACME_SPECS_REPOSITORY}`
- **Authorized path:** `specs/billing/overdue-invoice-notifications/`
```

The invoking environment sets `ACME_SPECS_REPOSITORY=acme/specs`. Without both
fields and a resolved value, an agent can draft the trio in conversation but
does not read or write an external repository.

## `requirements.md`

````md
## Objetivo

Notify the customer once when an invoice becomes overdue.

## Requisitos funcionais

- Identify invoices whose due date has passed and that have not been paid.
- Send one notification per overdue invoice.

## Requisitos não-funcionais

- The notification attempt must be observable in service logs.

## Critérios de aceite

- [AC-01] Given an unpaid invoice past its due date, when the overdue job runs, then
  one notification is requested; if delivery fails, the failure is recorded
  and the invoice is not marked as notified.

## Condições de falha

- A notification-provider error is logged with the invoice identifier and can
  be retried by the next scheduled run.

## Boundaries

| Status | Scope |
| --- | --- |
| ✅ | Detect and notify overdue invoices |
| ⚠️ | Retry cadence depends on the host project |
| 🚫 | Collecting payment |
````

## `design.md`

````md
## Stack

The host project's scheduler, invoice store, and notification provider.

## Arquitetura

```mermaid
flowchart LR
  Scheduler --> OverdueJob
  OverdueJob --> InvoiceStore
  OverdueJob --> Notifier
```

The job queries unpaid overdue invoices and asks the notifier to deliver one
message for each invoice.

## Contratos de componente

- `InvoiceStore.findOverdueUnpaid()` returns unpaid invoices past their due date.
- `Notifier.sendOverdue(invoice)` reports success or a recoverable error.

## Estratégia de teste

- Verify the job requests one notification for an overdue unpaid invoice.
- Verify a notifier error is recorded and does not mark the invoice notified.
````

## `tasks.md`

```md
- [ ] T01 [AC-01] Add overdue-invoice selection to the scheduled job.
  - Verification: `npm test -- overdue-job-selection`
- [ ] T02 [AC-01] Request notification delivery and record failures.
  - Verification: `npm test -- overdue-job-notification`

## Checkpoint

Confirm the host project's retry policy before adding retries.
```

## Proposing the path, and writing the trio

`ACME_SPECS_REPOSITORY` being resolvable is not authorization to write. The
outcome depends on two independent facts: whether the source resolved, and
whether the caller authorized that exact write.

A request produces the slug `overdue-invoice-escalations`, which the profile
above does not declare. The source resolved, so the agent does not stop at an
inline trio — it proposes where the trio belongs and how to put it there:

```md
**Write:** proposed path specs/billing/overdue-invoice-escalations/
```

with the exact write invocation it would run, so the caller can authorize it
verbatim rather than reconstruct it:

```text
resolve-target.sh --from-specs-repository "$ACME_SPECS_REPOSITORY"
git -C <checkout> checkout -b feat/overdue-invoice-escalations
```

Nothing is created, branched, or published by a proposal.

Told explicitly to write it, the agent resolves the target from the specs
repository (`source: specs-repository`), verifies the checkout before any
mutation, and reports the result:

```md
**Target:** acme/specs (checkout: /home/dev/specs)
**Profile:** billing (/home/dev/specs/.dr-agents/billing/PROFILE.md)
**Checkout state:** clean on main
**Write:** written to specs/billing/overdue-invoice-escalations/
```

It writes the three files on `feat/overdue-invoice-escalations` with
`git -C <checkout>`, registers the slug in the project's `index.md` in the same
commit, and opens the pull request through the adapter's `ship-change` flow,
dispatched `--repo acme/specs`. A dirty tree or an unexpected branch stops the
flow with the observed state instead of being committed around.

Where no checkout of `acme/specs` exists, the resolution is `remote-only` and
the same write goes through `remote-write.sh` with a manifest carrying the
three trio files and the updated `index.md`. No git command runs in the current
directory on the specs repository's behalf in either mode.

## Issue reference and execution

After the trio is accepted, the implementation issue records its exact source:

```md
Spec: acme/specs/specs/billing/overdue-invoice-notifications/
```

The executor verifies that the issue reference exactly matches the loaded
profile declaration, then reads `tasks.md` as read-only input. It performs the
tasks in order and runs each `Verification:` command after its task. Its
summary records `T01 → AC-01 → passed` and `T02 → AC-01 → passed`; a legacy
trio without these links is reported as traceability unavailable rather than
being inferred. At the checkpoint, it stops unless the caller explicitly
authorized continuous execution. The checkpoint does not authorize publication,
merge, or an unrelated external write.

The example is illustrative: its commands and components are not portable
requirements for consuming projects.
