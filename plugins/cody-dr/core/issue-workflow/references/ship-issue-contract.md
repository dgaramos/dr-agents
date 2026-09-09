# Ship-issue contract

## Inputs

Require the working branch and passing implementation summary. When
`ship-issue` is reached from an approved `execute-issue` lifecycle, that plan
approval authorizes shipping and no second confirmation is required. When
`ship-issue` is invoked standalone, require explicit user approval to ship
before publishing.

## Steps

1. Apply PR-body and delivery-metadata guidance discovered from
   `CONTRIBUTING.md` following
   [contribution-guidance-contract](contribution-guidance-contract.md).
2. Run the profile's quality command one final time on the current head. Stop
   if it fails.
3. Follow `ship-change-contract.md` to push and dispatch the matching adapter's
   `create-pr` App publisher with the issue-derived title and completed template.
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

**Branch:** `<branch-name>`
**Final quality gate:** <passed|failed: reason>
**PR:** <not requested|not published|<URL>>
**Metadata applied:** <labels, milestone, assignees, reviewers, Projects or none>
**Metadata verified:** <field → observed value, or failed field>
**Metadata publisher:** <verified App actor|personal fallback: @login|not published: reason>
**Contribution guidance:** <applied: <items> | not found | conflict: <description>>
```
