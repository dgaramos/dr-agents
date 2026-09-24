<!-- generated from core/issue-workflow/references/ship-issue-contract.md by bin/sync-plugin-core-bundles.sh -- do not edit -->
# Ship-issue contract

## Inputs

Require the working branch and passing implementation summary. When
`ship-issue` is reached from an approved `execute-issue` lifecycle, that plan
approval authorizes shipping and no second confirmation is required. When
`ship-issue` is invoked standalone, require explicit user approval to ship
before publishing.

## Target

Resolve the target through
`core/target-resolution/references/target-resolution-contract.md` before
loading a profile, and discover the profile at that target. Shipping requires
`checkout` mode: run every git command as `git -C <checkout>` and every
repository read as `gh --repo <target>`.

Verify the resolved checkout before any mutation — the final gate's commits,
the push, or the pull request — with `git -C <checkout> status --porcelain` and
`git -C <checkout> rev-parse --abbrev-ref HEAD`. A dirty working tree or a
branch other than the expected working branch means the checkout holds work
this flow did not produce. Report the observed state and stop with a handoff;
do not stash, reset, check out, or commit around it. Record the outcome in the
`Checkout state:` output field.

## Steps

1. Apply PR-body and delivery-metadata guidance discovered from
   `CONTRIBUTING.md` in the resolved checkout, following
   [contribution-guidance-contract](contribution-guidance-contract.md).
2. Run the profile's quality command one final time on the current head of the
   resolved checkout. Stop if it fails.
3. Follow `ship-change-contract.md` to push and dispatch the matching adapter's
   `create-pr` App publisher with the issue-derived title and completed template.
   The publisher is selected against the resolved target and dispatched
   qualified with it; the resulting PR's repository is verified to be the target.
4. Follow the same contract for App metadata publication and separate Project
   handling. User-owned Projects may use an authorized local `gh` account;
   unavailable Project access is reported as pending without blocking delivery
   unless the user explicitly requires it. Verify and name each publishing actor.
5. Emit the shipping output block before the enclosing `execute-issue` phase
   reports completion. If a required field cannot be applied or verified, emit
   a handoff with the PR URL and failed field; do not claim complete shipping.

## Output

```md
## Ship — <issue reference>

**Target:** <owner/repository (checkout: /absolute/path)>
**Profile:** <name (<checkout>/.dr-agents/<dir>/PROFILE.md) | none (no profile at checkout)>
**Branch:** `<branch-name>`
**Checkout state:** <clean on `<branch-name>` | dirty: <paths> | unexpected branch: `<observed>`>
**Final quality gate:** <passed|failed: reason>
**PR:** <not requested|not published|<URL>>
**PR publisher:** <verified App actor|personal fallback: @login|not published: reason>
**Metadata applied:** <labels, milestone, assignees, reviewers, Projects or none>
**Metadata verified:** <field → observed value, or failed field>
**Metadata publisher:** <verified App actor|personal fallback: @login|not published: reason>
**Contribution guidance:** <applied: <items> | not found | conflict: <description>>
```
