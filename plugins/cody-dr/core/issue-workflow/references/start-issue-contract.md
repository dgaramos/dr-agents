<!-- generated from core/issue-workflow/references/start-issue-contract.md by bin/sync-plugin-core-bundles.sh -- do not edit -->
# Start-issue contract

## Inputs

Require an approved `plan-issue` handoff. Do not create a branch before plan approval.

## Target

Resolve the target through
`core/target-resolution/references/target-resolution-contract.md` before
loading a profile. Discover the profile at that target with
`discover-project-profile.sh --root <checkout>`. Starting an issue creates a
branch, so it requires `checkout` mode; run every git command as
`git -C <checkout>` and every issue read as `gh --repo <target>`.

Verify the resolved checkout before any mutation, branch creation included,
with `git -C <checkout> status --porcelain` and
`git -C <checkout> rev-parse --abbrev-ref HEAD`. A dirty working tree, or a
branch other than the profile's base branch, means the checkout holds work this
flow did not produce. Report the observed state and stop with a handoff; do not
stash, reset, or branch over it. Record the outcome in the `Checkout state:`
output field.

## Steps

1. Load the target profile. Resolve the issue: title, body, acceptance
   criteria, dependencies, and labels.
2. Confirm all blocking dependencies are resolved before proceeding. If any
   dependency is open, report it and stop.
3. Inspect `CONTRIBUTING.md` in the resolved checkout, following
   [contribution-guidance-contract](contribution-guidance-contract.md). Record
   applicable branch-naming guidance or note its absence. A missing file is
   not a blocker. Surface any material conflict with the profile before
   proceeding.
4. Resolve the working branch name from the profile's branch naming convention,
   incorporating any non-conflicting `CONTRIBUTING.md` branch rules. Default
   to `<issue-number>-<slug>` when neither source specifies.
5. Create the working branch from the profile's base branch with
   `git -C <checkout> checkout -b <branch-name> <base>`. Report the branch
   name and base.

## Output

```md
## Start — <issue reference>

**Target:** <owner/repository (checkout: /absolute/path)>
**Profile:** <name (<checkout>/.dr-agents/<dir>/PROFILE.md) | none (no profile at checkout)>
**Issue:** <title>
**Branch:** `<branch-name>` from `<base>`
**Checkout state:** <clean on `<base>` | dirty: <paths> | unexpected branch: `<observed>`>
**Dependencies:** <all resolved|blocked by: #N, …>
**Contribution guidance:** <applied: <items> | not found | conflict: <description>>
**Next:** execute-issue (awaiting explicit approval)
```

Stop and emit a handoff block if any dependency is unresolved, the profile
is missing required branch values, or the resolved checkout is not clean on the
expected branch.
