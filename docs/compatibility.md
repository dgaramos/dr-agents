# Compatibility model

## Portable contract

The core contracts cover all portable behavior. They live in `core/` and are
the single behavioral source of truth for all adapters:

| Core area | Location |
| --- | --- |
| PR review | `core/pr-review/references/` |
| Issue authoring | `core/issue-authoring/references/` |
| Findings handling | `core/findings-handling/references/` |
| Issue-to-change workflow and test-first planning | `core/issue-workflow/references/` + `core/issue-workflow/skills/` |
| Target resolution | `core/target-resolution/` |

## Adapters

Both adapters implement the same portable contracts. Their intentional
differences are packaging and invocation only — they must not change the meaning
of any portable contract without documenting a version break here.

Both runtimes honor `DR_AGENTS_REPO_ROOTS`, a colon-separated list of local
directories whose immediate children may be target checkouts. Matching uses
the normalized `origin` remote, never the child directory name. When unset,
the resolver searches the parent of the current repository (or current
directory when outside git). This behavior is identical in Claude Code and
Codex.

## Canonical reviewer identities

The display name, GitHub App, and verified GitHub actor below are different
representations of one reviewer identity. Publisher availability is per
operation and is declared by the target profile; an unavailable operation does
not mean an App is inactive.

| Reviewer | Display name | GitHub App | Verified GitHub actor |
| --- | --- | --- | --- |
| Cody DR | Cody DR | Cody DR GitHub App | `cody-dr[bot]` |
| Claudio DR | Claudio DR | Claudio DR GitHub App | `claudio-dr[bot]` |

### Claudio DR (Claude Code)

| Aspect | Value |
| --- | --- |
| Platform | Claude Code |
| Plugin manifest | `.claude-plugin/plugin.json` |
| Reviewer agent | `plugins/claudio-dr/agents/claudio-reviewer.md` |
| Designer agent | `plugins/claudio-dr/agents/claudio-designer.md` |
| Spec agent | `plugins/claudio-dr/agents/claudio-spec.md` |
| Invocation | `/claudio-dr:review-pr <PR URL or ref>` |
| Issue authoring | `/claudio-dr:author-issue <problem statement>` |
| Implementation planning | `/claudio-dr:plan-implementation <issue>` |
| Agent invocation | `@claudio-reviewer review <ref>` or `/claudio-dr:design-discovery <request>` |
| Local validation | `claude plugin validate ./plugins/claudio-dr` |
| Local session | `claude --plugin-dir ./plugins/claudio-dr` |
| Update flow | bump version → `/plugin marketplace update` → `/plugin update claudio-dr@dr-agents` |

### Cody DR (Codex)

| Aspect | Value |
| --- | --- |
| Platform | Codex |
| Plugin manifest | `.codex-plugin/plugin.json` |
| Reviewer agent | `plugins/cody-dr/agents/cody-reviewer.md` |
| Designer agent | `plugins/cody-dr/agents/cody-designer.md` |
| Spec agent | `plugins/cody-dr/agents/cody-spec.md` |
| Invocation | `review-pr <PR URL or ref>` |
| Issue authoring | `author-issue <problem statement>` |
| Implementation planning | `plan-implementation <issue>` |
| Agent invocation | `@cody-reviewer review <ref>`, `@cody-author draft issue`, `@cody-executor execute issue #42`, `@cody-designer assess <request>`, or `@cody-spec draft <request>` |
| Local validation | `bin/check` + `codex --plugin-dir ./plugins/cody-dr` |
| Local session | `codex --plugin-dir ./plugins/cody-dr` |
| Update flow | bump version → reinstall from marketplace root → new thread |

### Documented differences that do not weaken the core

- **SKILL.md `name` field**: Claudio DR `review-pr/SKILL.md` omits the `name:`
  frontmatter key because Claude Code discovers skills by directory name. Cody
  DR includes `name: review-pr` for explicit Codex registration. Both load the
  same core contract.
- **Agent format**: both use the same markdown frontmatter schema (`name`,
  `description`, `skills`). The agent body differs only in reviewer identity.
- **Update mechanics**: Claude Code uses `/plugin update`; Codex requires a
  reinstall and a new thread. Neither difference affects review behavior.
- **Helper invocation style**: `claudio-helper` demonstrates slash-command style
  (e.g. `/claudio-dr:plan-implementation #42`) while `cody-helper` demonstrates
  agent-handle style (e.g. `@cody-designer assess this checkout flow`). This divergence is
  intentional and platform-driven — each adapter uses its platform's native
  invocation model. It is not a parity bug. Contributors extending either adapter
  should follow the invocation style of the target platform, not mirror the other
  adapter's syntax.
- **Spec authoring**: both adapters expose the portable spec-authoring contract
  through `claudio-spec` and `cody-spec`. Both write only with explicit caller
  authorization and a profile-declared target path; otherwise they return the
  trio without writing it.

## Profiles

A profile is the target repository's specialization layer. It supplies local
facts such as architecture, security constraints, quality commands, metadata
conventions, and publisher capability; it can strengthen the core contract but
cannot weaken its evidence or explicit-publication requirements.

Place one profile in the target repository at:

```text
.dr-agents/<project-name>/PROFILE.md
```

Global Cody DR and Claudio DR agents discover the sole matching profile from
the current repository. With no profile, an explicitly authorized generic
review may continue without project rules; lifecycle and publication actions
stop. With multiple profiles, the agents stop and ask which one applies rather
than selecting by directory order.

### Put project behavior in `PROFILE.md`

Keep every project-specific divergence from the portable contract in the
profile, including:

- the quality-gate command and known check limitations;
- branch naming, base branch, and merge policy;
- labels, milestone, assignees, reviewers, Project state, and PR template;
- required context files, architecture boundaries, and layer checklists;
- extra push remotes or deployment restrictions;
- an optional `## Spec source` declaration with an external repository (or one
  environment placeholder) and exact authorized trio path;
- the publisher dispatch contract, inputs, verified actor, and available or
  unavailable publisher modes.

This keeps `core/` portable and lets the same installed plugin operate in more
than one repository without copying target architecture or credentials.

### Keep local wrappers thin

Local agents are optional compatibility entrypoints. A wrapper should contain
only the reviewer identity, a binding to the installed adapter skill, and (when
needed for an older repository layout) an explicit profile reference. It must
not repeat review rules, lifecycle steps, checklists, publisher commands, or
quality gates.

As a rule of thumb, a local agent longer than roughly ten lines is probably
carrying behavior that belongs in `PROFILE.md`. Prefer the global plugin agents
(`cody-reviewer`, `cody-author`, `cody-executor`, `cody-designer`, `cody-findings`, and their Claudio
counterparts) for new projects; they discover the profile automatically.

### Example split

| Concern | Correct owner |
| --- | --- |
| Evidence threshold, finding format, explicit-publication boundary | `core/` |
| Cody/Claudio identity and platform invocation | `plugins/` |
| `bin/check`, architecture guidance, PR metadata, deployment policy | target `PROFILE.md` |
| A legacy alias that delegates to an installed skill | thin local wrapper |

## Migration: `.agent-review/` to `.dr-agents/`

Profile discovery was updated in v0.1.14 to scan `.dr-agents/*/PROFILE.md`
instead of `.agent-review/*/PROFILE.md`. This is a breaking convention change
for repositories that already carry a profile.

**Steps for consuming repositories:**

1. Rename the directory: `mv .agent-review .dr-agents`
2. No changes are needed inside `PROFILE.md` itself.
3. Update the dr-agents plugin to v0.1.14 or later.

There is no automated migration. Repositories that have not yet renamed the
directory will see no profile discovered until the rename is complete.
Workflows that rely on an explicit `--root` flag or hardcoded path must also be
updated to reference `.dr-agents/`.
