# Generic work sizing example

Portable illustration of
`core/work-sizing/references/work-sizing-contract.md`. The project, feature,
and file names below are placeholders.

## Scenario

A spec for an export feature carries six acceptance criteria:

- `AC-01` the export button is disabled while no rows are selected
- `AC-02` the button becomes enabled once at least one row is selected
- `AC-03` the export writes a CSV with a header row
- `AC-04` the export escapes embedded separators and quotes
- `AC-05` an export of zero rows reports an error instead of writing a file
- `AC-06` the export runs off the request thread

## Fragmented breakdown

A first draft produced one task per criterion:

```text
- [ ] T01 [AC-01] disable the export button with no selection
  - Verification: unit test on the button state
- [ ] T02 [AC-02] enable the export button on selection
  - Verification: unit test on the button state
- [ ] T03 [AC-03] write the CSV header row
  - Verification: unit test on writer output
- [ ] T04 [AC-04] escape separators and quotes
  - Verification: unit test on writer output
- [ ] T05 [AC-05] reject an empty export
  - Verification: unit test on writer output
- [ ] T06 [AC-06] move the export off the request thread
  - Verification: integration test on the job queue
```

Six tasks for six criteria. Every criterion maps to a task, so the traceability
rule is satisfied — and the breakdown is still wrong. `T01` and `T02` are two
halves of one conditional in one component. `T03`, `T04`, and `T05` are three
branches of one writer, changed in one edit and reviewed as one.

Applying the signals: fragments touching the same file in the same change, and
a task count equal to the criterion count. Applying the justification rule to
each boundary in turn, none of the five boundaries can name a decision that is
expensive to reverse, a dependency unsatisfiable in one change, or a review
that cannot be done as one.

## Merged breakdown

```text
- [ ] T01 [AC-01, AC-02] gate the export button on selection state
  - Verification: unit tests covering empty and non-empty selection
- [ ] T02 [AC-03, AC-04, AC-05] implement the CSV writer
  - Verification: unit tests covering the header, escaping, and the empty-export error
- [ ] T03 [AC-06] move the export onto the background job queue
  - Boundary: the queue is a dependency that cannot be satisfied inside the
    writer change — the writer ships and is reviewable without it, and backing
    the queue out later does not touch the writer.
  - Verification: integration test asserting the request returns before the file is written
```

Three tasks, six criteria, every criterion still named. The one surviving
boundary carries its forcing reason on the line where a reviewer reads it. The
two boundaries that could not state one were merged away.

## What to look for

- Every criterion is named by some task. Coverage did not change.
- The count dropped from six to three and no traceability was lost, because
  traceability lives in the mapping.
- Exactly one boundary is justified in writing. A reviewer can disagree with
  that one sentence, which is the point of requiring it.
