<!-- generated from core/issue-workflow/references/workflow-contract.md by bin/sync-plugin-core-bundles.sh -- do not edit -->
# Portable issue-to-change workflow contract

## Profile-owned fields

The following fields belong to the target profile and must never be hardcoded
in core workflow behavior:

- branch naming convention and base branch;
- required PR metadata: labels, milestone, reviewers, Projects, PR template;
- remote names and push targets;
- merge policy (squash, merge commit, rebase);
- quality command and known check limitations.

When no profile is loaded, use the generic portable defaults where they are
defined. Stop only when a required value cannot be resolved without a material
out-of-scope decision.

## Quality gate

Run the profile's quality command after every logical implementation unit and
again before shipping. If the quality command fails at any point:

- stop the current phase;
- do not claim the work is done;
- do not proceed to the next phase;
- report the failure with the command output.

## Publication boundary

An explicit request to execute an issue authorizes creating its working branch,
committing, pushing, and opening a fully populated pull request. Do not ask
for a second confirmation as the workflow reaches push or PR creation. Merge
remains separately authorized.

Review, comment, reply, and thread-resolution publication remain separately
authorized actions; issue execution never authorizes them.

## Handoff at stop

When a phase stops without completing (quality gate failure, missing
permission, unresolved dependency, or material out-of-scope decision), emit a
handoff block:

```md
## Handoff — <phase name>

**Stopped at:** <reason>
**Last verified head:** `<sha or none>`
**Next step:** <what the user must do to continue>
```
