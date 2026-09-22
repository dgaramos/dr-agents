# CLAUDE.md

## What this repo is

Private catalog of reusable, cross-model agent workflows. Behavior is defined
in `core/`, consumed by thin adapter plugins, and tuned per project through
profiles. This is the source of truth for Claudio DR (Claude Code) and Cody DR
(Codex) review, findings-handling, issue-authoring, and lifecycle skills.

## Structure and boundaries

```text
core/                    Portable contracts — never touch target-project specifics here
plugins/claudio-dr/      Claude Code adapter — identity and platform mechanics only
plugins/cody-dr/         Codex adapter — identity and platform mechanics only
profiles/                Project profiles — architecture, commands, metadata, publishers
examples/                One generic example per core skill area
docs/                    Compatibility, installation, development docs
bin/check                Catalog quality gate — run before every handoff
```

**Core** contains only portable, model-neutral contracts. Do not add
repository-specific commands, credentials, labels, branch names, or remote
references to any file under `core/`.

**Adapters** contain only reviewer identity and platform-specific invocation.
Do not embed portable contract content (finding tables, confidence thresholds,
summary templates) in adapter SKILL.md files — reference the core file by path.

**Profiles** contain everything project-specific. They strengthen the core;
they never weaken the evidence threshold or the explicit-publication boundary.

## Architecture

Read [docs/architecture.md](docs/architecture.md) for the full layer diagram,
data flow, publication model, and how `bin/check` enforces layer boundaries.
The short version: `core/` → contracts, `plugins/` → identity + platform,
`profiles/` → project rules.

## Quality gate

Before every commit or handoff:

```bash
bin/check
```

This verifies required paths, SKILL.md frontmatter, adapter drift, parity
between Claudio and Cody adapters, and the absence of tracked secrets.

## Commit style

Conventional Commits:

```text
type(scope): description
```

Allowed types: `feat`, `fix`, `docs`, `refactor`, `chore`, `test`, `build`, `ci`.
Scope examples: `review`, `workflow`, `profile`, `claude`, `codex`, `core`.

## Working on issues

One branch and one PR per issue. Name branches `<issue-number>-<type>/<slug>`.
Link PRs to their issue. Preserve labels, milestone, assignee, and Project
board status.

## Adding a core skill

1. Create `core/<area>/SKILL.md` and `core/<area>/references/<contract>.md`.
2. Add a generic example under `examples/`.
3. Add thin adapter skills in both `plugins/claudio-dr/` and `plugins/cody-dr/`
   that reference the core skill by path.
4. Add all new paths to `required_paths` in `bin/check`.
5. Add parity and drift checks to `bin/check` as needed.
6. Run `bin/check` — it must pass before opening the PR.

## Adding a profile

1. Create `profiles/<project>.md` following the profile-contract at
   `core/pr-review/references/profile-contract.md`.
2. Include: project identity, required context, architecture boundaries,
   quality command, skill mapping, PR metadata rules, and publisher dispatch
   contract (modes, secret names only — never values).
3. Add the path to `required_paths` in `bin/check`.

## Tooling pitfalls

Each of these produced a false result during real work. Check them before
trusting a verification.

- **`bin/install --repo` targets the current working directory, not `HOME`.**
  A test that fakes `HOME` and runs it from the catalog checkout writes into
  the catalog's own `.claude/`. Run install tests from a scratch directory.
- **A skill's current working directory is not necessarily its target.**
  Earlier flows assumed the cwd was the repository named by a PR, issue, or
  specs source. Resolve the target first and match local checkouts by `origin`;
  never infer the target from a directory name.
- **`gh pr edit --milestone` takes the milestone title, not its number.**
  `--milestone 3` fails with `'3' not found`; pass the title the profile's
  milestone number resolves to.
- **`compgen -G` is not an existence check.** With no glob metacharacters it
  returns the pattern unchanged, so a stale path reads as present. Use `[ -e ]`
  or a real `glob` call.
- **A pipeline reports the last command's exit status.** `docker build ... |
  tail` returns `tail`'s zero while the build fails. Check the status of the
  command that matters, or set `pipefail`.
- **Hand-maintained lists drift silently.** Derive sets from the tree instead
  of enumerating names: `bin/install` derives its stub set from
  `plugins/*/workflows/`, and `verify-publisher-dispatch.sh` compares a profile
  against `.github/workflows/` in both directions. A count or a fixed list that
  passes today fails for being correct the day something is added.

## Publication safety

An explicit issue-execution request authorizes branch creation, implementation,
validation, commits, push, and PR creation. Reviews, replies, thread
resolution, and issue creation still require separate explicit authorization.
Never store or read credentials; reference secret names only. Return
publication-ready output as `not published` when a separately authorized
publisher action has no configured publisher.

## Never do

- Hardcode branch names, labels, commands, or remotes in `core/`.
- Duplicate contract content across adapters — reference the core file.
- Commit credentials, tokens, private keys, or installation tokens.
- Publish review content or merge without explicit user authorization; do not
  interrupt an explicitly authorized issue execution before push or PR creation.
- Skip `bin/check` before handoff.
