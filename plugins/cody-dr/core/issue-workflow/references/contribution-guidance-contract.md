<!-- generated from core/issue-workflow/references/contribution-guidance-contract.md by bin/sync-plugin-core-bundles.sh -- do not edit -->
# Contribution-guidance discovery contract

## Purpose

When a target repository provides `CONTRIBUTING.md`, lifecycle skills inspect
it before branch creation, implementation, and shipping to surface applicable
branch naming, commit format, validation, PR, and metadata conventions. The
profile remains the authoritative source of delivery rules; `CONTRIBUTING.md`
supplements the profile rather than replacing or weakening it.

An absent `CONTRIBUTING.md` is not a blocker. The lifecycle continues under
portable and profile rules without inventing conventions.

## Discovery step

At the start of `start-issue`, after loading the profile and before creating
the working branch:

1. Inspect `CONTRIBUTING.md` at the repository root. If the file does not
   exist, record "no CONTRIBUTING.md found" and proceed without failure.
2. If the file exists, read it and extract applicable guidance in these
   categories:
   - **Branch naming** — any convention that differs from the profile default.
   - **Commit format** — type, scope, trailer, or sign-off rules.
   - **Validation** — commands, scripts, or checklists to run before committing
     or opening a PR.
   - **PR body / template** — section structure, labels, linking conventions.
   - **Delivery metadata** — milestone, assignee, project, or status rules.
3. Record the extracted guidance. Apply each applicable item during the
   corresponding lifecycle phase (branch creation, commits, validation,
   shipping).

## Precedence

Profile rules take precedence over `CONTRIBUTING.md`. When a rule in
`CONTRIBUTING.md` materially conflicts with the profile's delivery guidance —
for example a different base branch, a conflicting label policy, or an
incompatible commit format — surface the material conflict and request
direction rather than silently choosing one over the other.

A non-material difference (a style preference that does not affect delivery
correctness) may be applied from either source without blocking the lifecycle.

## Failure modes

- **Absent file:** not a blocker; continue under profile and portable rules.
- **Unreadable or unparseable file:** record the problem, continue under
  profile rules, and note the skipped guidance in the phase output.
- **Material conflict with profile:** stop, report the conflicting rules, and
  request explicit direction before proceeding.
- **Ambiguous rule:** surface the ambiguity in the phase output and apply the
  profile default.

## Phase application

| Phase | Applicable guidance |
|---|---|
| `start-issue` | Branch naming, base branch |
| `implement-issue` | Commit format, validation commands, sign-off rules |
| `ship-change` | PR body structure, delivery metadata, validation checklist |

## Output note

Each lifecycle phase that inspects `CONTRIBUTING.md` reports the outcome in
its output block:

```md
**Contribution guidance:** <applied: <items> | not found | conflict: <description>>
```
