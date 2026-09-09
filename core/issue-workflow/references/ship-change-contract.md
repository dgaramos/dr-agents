# Ship-change contract

## Inputs

Require the working branch and the implementation summary from `implement-issue`.
Do not ship without confirmed passing quality gates.

## Steps

1. Apply PR-body and delivery-metadata guidance discovered from `CONTRIBUTING.md`
   following [contribution-guidance-contract](contribution-guidance-contract.md).
   A missing file is not a blocker. Surface any material conflict with the
   profile before opening the PR.
2. Run the profile's quality command one final time on the current head. Stop
   if it fails.
3. Prepare the PR:
   - Title: derived from the issue title.
   - Body: when `.github/pull_request_template.md` exists in the repository,
     read that file, fill every section with the change-specific answer or an
     explicit `Not applicable`, and pass the completed text to
     the profile's `create-pr` App publisher as its body input. Retain every
     heading; do not
     replace the template with a free-form summary. Opening a PR with a
     free-form body when a template exists is a contract violation. When no
     template file is present, use the implementation summary and acceptance
     criteria checklist as the body.
   - Metadata: labels, milestone, assignees, reviewers, and Projects from the profile.
4. Push the branch using the profile's configured transport. Dispatch its
   `create-pr` publisher as the current adapter App with title, completed body,
   head branch, and base branch. Wait for completion and verify the PR's author,
   repository, branches, title, and body. Use structured inputs or a body file;
   never interpolate Markdown into executable shell text. Apply
   `core/pr-review/references/publication-routing-contract.md` when the App
   is unavailable, including repositories without a profile or App installation.
   Announce and verify the personal `gh` fallback. The issue-execution request
   authorizes these normal delivery actions; do not ask again.
5. Dispatch the profile's `apply-pr-metadata` App publisher for the declared
   labels, milestone, assignees, and supported reviewers. Resolve values from
   the issue and profile. Require only fields actually declared as required;
   an absent milestone, empty label list, or repository without Projects must
   not invent a requirement. Wait for and verify the App result using REST
   issue/pull endpoints without querying Project fields. A failure applying
   ordinary metadata is a failed publication, not a successful warning. If its
   App publisher is unavailable, apply the same fields through the personal
   fallback selected by the publication routing contract.
6. Treat Projects as a separate capability. Organization Projects can use an
   installation token with organization Projects write permission. User-owned
   Projects use the authorized local `gh` account when that fallback is allowed
   by the user or profile; report that account separately from the App.
   Do not request organization Projects permissions from the ordinary metadata
   token or retry inaccessible Projects during unrelated operations.
   If Project access is unavailable, report `Project pending` and continue
   delivery unless the user explicitly makes it a blocking requirement. Never
   report unverified Project membership or status as applied.
7. Emit a handoff with the PR URL and failed field if a required non-Project
   field cannot be verified. Report App publication and personal Project
   updates separately.

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

Do not publish review, comment, reply, or thread-resolution content as part of
shipping unless the user separately authorizes that publication.
