<!-- generated from core/issue-workflow/references/plan-issue-contract.md by bin/sync-plugin-core-bundles.sh -- do not edit -->
# Plan-issue contract

`plan-issue` is read-only. It loads the profile and issue, produces the complete test-first plan, sends it with `SendMessage to: "main"`, then stops. Do not create a branch, edit files, commit, push, or publish before explicit approval of `start-issue`.

```md
## Plan — <issue reference>
**Plan:** <complete plan>
**Next:** start-issue (awaiting explicit approval)
```
