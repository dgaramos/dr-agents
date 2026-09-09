# Agent Workflows profile

Use this profile when reviewing this repository. Read `AGENTS.md`, `README.md`,
`CONTRIBUTING.md`, the issue, changed plugin manifests, both adapter skills, and
their review contracts. Run `bin/check` before handoff.

## Adapter release discipline

Any change below `plugins/cody-dr/` or `plugins/claudio-dr/` is an installable
adapter change. In the same pull request, bump the affected plugin's patch
version in both its manifest and its matching marketplace entry; do not bump an
unaffected adapter just to keep the numbers equal. Verify those two values
match before handoff.

Treat adapter capability parity as bidirectional: every user-facing skill,
agent, workflow entrypoint, and portable-contract capability added to Claudio
DR must have an equivalent Cody DR counterpart, and vice versa. Keep the
portable behavior in `core/`; adapters may differ only for documented identity
or platform mechanics. If an equivalent is intentionally unavailable, document
the reason and the user-visible limitation in `docs/compatibility.md` and add a
check that prevents the divergence from becoming accidental.

For Claudio DR changes, run `claude plugin validate ./plugins/claudio-dr` as
well as `bin/check`, then load the plugin with `claude --plugin-dir
./plugins/claudio-dr` when a runtime validation is required. Codex has no
standalone manifest validator: run `bin/check`, then load
`codex --plugin-dir ./plugins/cody-dr` for runtime validation. Record any
runtime service-limit failure separately from manifest or catalog validation.

## Independent PR review

Use Claudio DR's `review-pr` skill (or the `claudio-reviewer` agent) as an
independent reviewer against an explicit pull request URL, including a PR
authored by another contributor. In the review request, name this profile
explicitly:

```text
Review <PR URL> with Claudio DR using the dr-agents profile at
profiles/dr-agents.md.
```

Before reviewing, Claudio DR must load this profile and read `CLAUDE.md`, the
issue and pull-request context, every changed skill and its referenced portable
contract, plus `bin/check` output for the reviewed head. Apply the catalog
checklist: keep portable behavior in `core/`, keep model-specific mechanics in
`plugins/`, keep target-project rules in `profiles/`, preserve Codex/Claude
adapter parity where the portable contract applies, require a generic example
for a core-contract change, and reject any credential or implicit-publication
change. Publish a review only with explicit authorization, through the Claudio
DR publisher, and verify the resulting author is `claudio-dr[bot]`.

## PR metadata

- **Labels:** `enhancement` plus scope labels selected by the issue
- **Milestone:** `3`
- **Assignee:** `dgaramos`
- **Project:** `Agent Workflows` (`11`), status `In Progress` while active
- **Reviewers:** only when explicitly requested

After shipping, apply and verify ordinary metadata as the current adapter App.
The user-owned Project is separate: use the authorized local `gh` account and
report its actor, or report Project pending without blocking delivery.

Dispatch the matching `apply-pr-metadata` publisher workflow with base `main`,
the selected labels, milestone number `3`, and assignee `dgaramos`. Wait for
and verify the matching App result; ordinary metadata failure must be reported
as a failure. Use Project owner `dgaramos`, number `11`, status `In Progress`
only in the separate local Project step. Omit Project inputs from the App
dispatch. Reviewers remain absent unless explicitly requested.

## PR description

Use [`.github/pull_request_template.md`](../.github/pull_request_template.md).
Retain every section and fill it with the change-specific answer; mark a
section `Not applicable` rather than deleting it. The `What changes` section
explains the intent and workflow impact, not a diff inventory. Include
`Closes #<issue-number>` in Additional context.

## Publication contract

Use `core/pr-review/references/reviewer-identity-contract.md`. Cody DR, the
Cody DR GitHub App, and `cody-dr[bot]` are one reviewer identity; Claudio DR,
the Claudio DR GitHub App, and `claudio-dr[bot]` are likewise one identity.

An explicit issue-execution request authorizes its normal delivery, including
branch creation, commits, push, PR creation, and complete PR metadata. Review,
comment, reply, resolution, and issue-creation publication remain separately
authorized. The local publisher configuration is
discovered from repository variables and secrets by name only: Cody uses
`CODY_DR_CLIENT_ID` and `CODY_DR_PRIVATE_KEY`; Claudio uses
`CLAUDIO_DR_CLIENT_ID` and `CLAUDIO_DR_PRIVATE_KEY`. Never read, print, copy,
or commit their values.

The target publisher must use an installation token, publish as the matching
GitHub App, then verify its author, event, and target PR/thread. It needs Pull
requests read/write for reviews and replies, and Issues read/write for resolving
conversations and creating issues. If no target publisher documents the
requested mode, return publication-ready text as `not published`.

## Cody DR publisher modes

- `create-pr`: `.github/workflows/publish-cody-pr.yml`
- `review`: `.github/workflows/publish-cody-review.yml`
- `apply-pr-metadata`: `.github/workflows/publish-cody-pr-metadata.yml`
- `reply`: `.github/workflows/publish-cody-reply.yml`
- `resolve-thread`: `.github/workflows/publish-cody-resolve.yml`
- `create-issue`: `.github/workflows/publish-cody-issue.yml`

The review publisher accepts a reviewed head SHA plus an optional review body,
inline findings, thread replies, and thread resolutions. A profile that lacks one of those modes
must report only that operation as unavailable, rather than claiming that the
Cody DR App is inactive.

Issue creation is dispatched with a title, Markdown body, and optional labels,
assignees, and milestone number. The workflow must verify the created author is
`cody-dr[bot]`; a different author is a failed publication, not a fallback.

## Explicit review requests

The PR template lets contributors request Cody DR, Claudio DR, or no agent
review. It is a collaboration signal, not an automation trigger: an authorized
model executor must still be explicitly asked to review the PR and may dispatch
the matching publisher only after preparing a verified manifest. The checkbox
never authorizes approval, merge, issue creation, or issue execution.

Use the same request shape for both reviewers. The only differences are the
adapter identity and its publisher workflow.

## Personal publication fallback

For every authorized publication, follow
`core/pr-review/references/publication-routing-contract.md`. Use the matching
App whenever available. Personal fallback requires observed evidence that
the operation is unavailable, not just a missing profile or generic error.
Announce the reason, verify the actual actor, and label the fallback. The
existing authorization covers the route change; it does not authorize extra
publications. Inspect uncertain outcomes before retrying under any account.

Neither App submits `REQUEST_CHANGES`. Findings are published as a `COMMENT`;
whether they block merging is decided by a human reviewer.

## Claudio DR publisher modes

- `create-pr`: `.github/workflows/publish-claudio-pr.yml`
- `review`: `.github/workflows/publish-claudio-review.yml`
- `apply-pr-metadata`: `.github/workflows/publish-claudio-pr-metadata.yml`
- `reply`: `.github/workflows/publish-claudio-reply.yml`
- `resolve-thread`: `.github/workflows/publish-claudio-resolve.yml`
- `create-issue`: `.github/workflows/publish-claudio-issue.yml`

The review publisher accepts a reviewed head SHA plus an optional review body and
inline findings. The dedicated thread publishers verify that the GraphQL review-thread
ID belongs to the supplied pull request before replying or resolving it; reply
publication additionally verifies `claudio-dr[bot]` as the author. Missing modes follow the same
unavailable-operation behavior; their absence does not indicate an inactive
Claudio DR App.

Issue creation follows the same inputs and verification requirement, with
`claudio-dr[bot]` as the expected author.

## Pull request creation

Both `create-pr` publishers accept `title`, completed Markdown `body`,
`head_branch`, and `base_branch`. Dispatch on the repository default branch,
wait for completion, and verify the resulting App author, repository, branches,
title, and body. An identical retry reuses the existing PR; a mismatched
existing PR fails verification. Creating a PR requires Pull requests write.

## Boundaries

Keep portable behavior in `core/`, model mechanics in `plugins/`, and this
repository's operational integration in `profiles/`. Do not add credentials,
automatic publication, or target-project rules to the shared contract.
