# Contributing Guide

This guide walks you through the full lifecycle of a contribution to this
repository, from picking up an issue to having a merged pull request. Follow
it top-to-bottom on your first contribution; use it as a reference afterwards.

## Repository structure at a glance

```text
core/                    Portable, model-neutral contracts — single source of truth
  pr-review/             PR review protocol and reporting
  findings-handling/     Triage, fix, defer, and reject findings
  issue-authoring/       Draft and publish structured GitHub issues
  issue-workflow/        start → plan → implement → ship lifecycle contracts
  profile-discovery/     Profile location and loading contract

plugins/claudio-dr/      Claude Code adapter — identity and platform mechanics only
plugins/cody-dr/         Codex adapter — identity and platform mechanics only

profiles/                Project-specific rules: architecture, commands, metadata, publishers
examples/                One generic, safe usage example per core skill area
docs/                    Architecture, compatibility, development, and installation docs
bin/check                Catalog quality gate — run before every handoff
```

**The three-layer rule:** portable behavior belongs in `core/`, model-specific
mechanics belong in `plugins/`, and project rules belong in `profiles/`. Never
move a layer's content into another layer.

## Step 1 — Pick up an issue

1. Find an open issue in the
   [Agent Workflows Project](https://github.com/users/dgaramos/projects/11).
2. Assign it to yourself and move it to **In Progress** on the board.
3. Read the issue body, acceptance criteria, and any linked issues.
4. Identify which layer the change belongs to: `core/`, `plugins/`, `profiles/`,
   or `docs/`. Do not scope a project-specific fix into `core/`.

## Step 2 — Create the working branch

Branch names follow the pattern `<issue-number>-<type>/<slug>`:

```bash
git checkout -b 42-feat/add-findings-contract
git checkout -b 55-docs/update-architecture
```

Use the conventional-commit type that matches the change. Treat the issue
number as the canonical anchor; use the same number across the branch, commit,
and PR.

## Step 3 — Understand the implementation rules

Before editing, read the contracts that govern the area you are changing:

| Area | Contract to read |
| --- | --- |
| `core/` changes | `core/<area>/references/<contract>.md` |
| Plugin changes | The core contract the plugin references |
| Profile changes | `core/pr-review/references/profile-contract.md` |
| New core skill | All four: core contract, adapter parity, example, `bin/check` path |

Key invariants to keep:

- **Portable behavior only in `core/`.** No repository-specific commands,
  branch names, credentials, labels, or remote references.
- **Adapters reference, not embed.** Adapter SKILL.md files point to the core
  contract by path; they never copy finding tables, thresholds, or templates.
- **Profiles strengthen the core.** A profile may add stricter rules; it cannot
  weaken evidence thresholds or the explicit-publication boundary.
- **No secrets anywhere.** Publisher configuration names secrets only; values
  must never appear in any tracked file.

## Step 4 — Implement and validate incrementally

Run the quality gate after each logical unit of work:

```bash
bin/check
```

`bin/check` verifies required paths, SKILL.md frontmatter, adapter drift,
Claudio/Cody parity, and the absence of tracked secrets. A failing gate is a
blocker — fix it before moving to the next step.

When the change is in `core/`, also run the test suites:

```bash
pytest tools/ tests/ -v
```

154 tests cover custom tools (unit), repo structure consistency, and zsh file
syntax (integration).

## Step 5 — Commit using Conventional Commits

Format:

```text
type(scope): imperative summary
```

Allowed types: `feat`, `fix`, `docs`, `refactor`, `chore`, `test`, `build`, `ci`.

Scope examples: `review`, `workflow`, `profile`, `claude`, `codex`, `core`.

Every commit in this repository includes the `claudio-dr[bot]` co-author
trailer so that automated tooling can attribute work correctly:

```bash
git commit -m "docs(contributing): add contributor guide

Co-Authored-By: claudio-dr[bot] <318764128+claudio-dr[bot]@users.noreply.github.com>"
```

Commit descriptions are concise, imperative, and written in English. Include
`Closes #<issue-number>` in the pull request description, not in the commit
message.

## Step 6 — Open a pull request

1. Push the branch and open a PR against `main`:

   ```bash
   git push -u origin <branch-name>
   gh pr create --base main --title "type(scope): summary" --body "$(cat <<'EOF'
   ...filled template...
   EOF
   )"
   ```

2. Use `.github/pull_request_template.md` as your PR body. **Fill in every
   section.** Mark a section `Not applicable` rather than deleting it. The
   `What changes` section explains intent and workflow impact — not a diff
   inventory.

3. Include `Closes #<issue-number>` in the **Additional context** section for
   each issue the PR resolves.

4. Set the correct scope checkboxes in the template. A single PR may touch
   multiple scopes; check all that apply.

## Step 7 — Apply PR metadata via the publisher workflow

After the PR is open, dispatch the Claudio DR metadata publisher to apply
labels, milestone, assignee, and Project board status:

```bash
gh workflow run publish-claudio-pr-metadata.yml \
  --repo dgaramos/dr-agents \
  -f pr_number=<pr-number> \
  -f labels="enhancement,docs" \
  -f milestone=3 \
  -f assignee=dgaramos \
  -f project_owner=dgaramos \
  -f project_number=11 \
  -f project_status="In Progress"
```

Wait for the run to complete and verify every field on the PR. If the App
cannot apply a field (for example, a user-owned Project), an explicitly
authorized personal account may apply that field as a fallback. Report it as a
personal fallback; never represent it as Claudio DR or Cody DR.

## Step 8 — Request a review (optional)

Agent review is a separate, explicitly authorized action. It does not happen
automatically. To request Claudio DR to review the PR, open a new conversation
with Claude Code and ask:

```text
Review <PR URL> with Claudio DR using the dr-agents profile at
profiles/dr-agents.md.
```

The PR template's review-request checkboxes are a collaboration signal — they
do not trigger a model or authorize approval.

## How the publisher workflows work

Publisher workflows authenticate as the matching GitHub App (Claudio DR or
Cody DR), perform the requested action, and verify the resulting author is
`claudio-dr[bot]` or `cody-dr[bot]`. A mismatch is a failed publication, not
a fallback. Available modes:

| Mode | Claudio DR workflow | Cody DR workflow |
| --- | --- | --- |
| Apply PR metadata | `publish-claudio-pr-metadata.yml` | `publish-cody-pr-metadata.yml` |
| Post review | `publish-claudio-review.yml` | `publish-cody-review.yml` |
| Reply to thread | `publish-claudio-reply.yml` | `publish-cody-reply.yml` |
| Resolve thread | `publish-claudio-resolve.yml` | `publish-cody-resolve.yml` |
| Create issue | `publish-claudio-issue.yml` | `publish-cody-issue.yml` |

Neither App submits `REQUEST_CHANGES`. Findings are published as a `COMMENT`;
whether they block merging is a human decision.

## Adding a new core skill

Follow this checklist when the change introduces a new portable contract:

1. Create `core/<area>/SKILL.md` and `core/<area>/references/<contract>.md`.
2. Add a generic example under `examples/`.
3. Add thin adapter skills in both `plugins/claudio-dr/` and `plugins/cody-dr/`
   that reference the core skill by path. Keep adapter parity.
4. Add all new paths to `required_paths` in `bin/check`.
5. Add parity and drift checks to `bin/check` as needed.
6. Run `bin/check` — it must pass before opening the PR.

## Adding a profile

1. Create `profiles/<project>.md` following
   `core/pr-review/references/profile-contract.md`.
2. Include: project identity, required context, architecture boundaries,
   quality command, skill mapping, PR metadata rules, and publisher dispatch
   contract (modes, secret names only — never values).
3. Add the path to `required_paths` in `bin/check`.

## Running tests locally

```bash
# Full suite
pytest tools/ tests/ -v

# Quality gate only
bin/check
```

Install pytest with `brew install pytest` (macOS) or `pip install pytest`.

## Common mistakes

| Mistake | Correct approach |
| --- | --- |
| Putting project-specific rules in `core/` | Move them to `profiles/` |
| Embedding portable contract content in an adapter | Reference the core file by path |
| Storing a secret value in a profile | Reference the secret name only |
| Opening a PR without running `bin/check` | Always run `bin/check` first |
| Amending a published commit without asking | Create a new commit |
| Merging without review and passing CI | Wait for the `quality` check and review |
