# Ship-change contract

## Inputs

Require the working branch and the implementation summary from `implement-issue`.
Do not ship without confirmed passing quality gates.

## Target

Resolve the target through
`core/target-resolution/references/target-resolution-contract.md` before
loading a profile or running any repository-dependent command. Discover the
profile at that target with `discover-project-profile.sh --root <checkout>`;
never apply the current directory's profile to another repository.

Shipping mutates a repository, so it requires `checkout` mode. Run every git
command as `git -C <checkout>` — `git -C <checkout> status`,
`git -C <checkout> push` — and every repository read as `gh --repo <target>`.
A bare git command runs in whatever directory the agent started in, which is
not necessarily the target.

Verify the resolved checkout before any mutation — the final gate's commits,
the push, or the pull request — with `git -C <checkout> status --porcelain` and
`git -C <checkout> rev-parse --abbrev-ref HEAD`. A dirty working tree or a
branch other than the expected working branch means the checkout holds work
this flow did not produce. Report the observed state and stop with a handoff;
do not stash, reset, check out, or commit around it. Record the outcome in the
`Checkout state:` output field. This gate applies to a standalone `ship-change`
invocation as much as to one reached through `ship-issue`.

## Steps

1. Apply PR-body and delivery-metadata guidance discovered from `CONTRIBUTING.md`
   in the resolved checkout, following
   [contribution-guidance-contract](contribution-guidance-contract.md).
   A missing file is not a blocker. Surface any material conflict with the
   profile before opening the PR.
2. Run the profile's quality command one final time on the current head of the
   resolved checkout. Stop if it fails.
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
4. Select each publisher against the resolved target, not against the current
   directory's repository: run
   `core/pr-review/scripts/select-publisher.sh <target>
   .github/workflows/publish-<agent>-pr.yml` for the PR and
   `core/pr-review/scripts/select-publisher.sh <target>
   .github/workflows/publish-<agent>-pr-metadata.yml` for its metadata.
5. Push the branch with `git -C <checkout> push` using the profile's configured
   transport. Dispatch the selected `create-pr` publisher as the current adapter
   App with title, completed body, head branch, and base branch. Qualify the
   dispatch with the resolved target — `gh workflow run <workflow>
   --repo <target>` or an equivalent repository-qualified API call — so that an
   unqualified command can never run against the current directory's
   repository. Selecting the publisher at the target and then dispatching
   unqualified is a failed publication, not a recoverable detail.
   Wait for completion and verify the PR's author,
   repository, branches, title, and body. The PR's repository must be the
   resolved target; a PR opened anywhere else is a failed publication
   regardless of its content, and verifying the author alone proves only who
   published, not where. Report the verified author in the
   `PR publisher:` output field. Route the PR independently of every other
   operation: an authorized fallback for Projects, metadata, or an issue never
   authorizes creating the PR or authoring its commits outside the App. When
   any operation degrades to the personal account, name that operation and its
   actor in the output; silence is a contract violation, not a clean result.
   Use structured inputs or a body file; never interpolate Markdown into
   executable shell text. Apply
   `core/pr-review/references/publication-routing-contract.md` when the App
   is unavailable, including repositories without a profile or App installation.
   A permission error or a failed enumeration is unknown availability, not
   proven absence: it returns `not published` without a personal attempt.
   Announce and verify the personal `gh` fallback. The issue-execution request
   authorizes these normal delivery actions; do not ask again.
6. Dispatch the selected `apply-pr-metadata` App publisher, likewise qualified
   with the resolved target, for the declared
   labels, milestone, assignees, and supported reviewers. Resolve values from
   the issue and profile. Require only fields actually declared as required;
   an absent milestone, empty label list, or repository without Projects must
   not invent a requirement. Wait for and verify the App result using REST
   issue/pull endpoints without querying Project fields. A failure applying
   ordinary metadata is a failed publication, not a successful warning. If its
   App publisher is unavailable, apply the same fields through the personal
   fallback selected by the publication routing contract.
7. Treat Projects as a separate capability. Organization Projects can use an
   installation token with organization Projects write permission. User-owned
   Projects use the authorized local `gh` account when that fallback is allowed
   by the user or profile; report that account separately from the App.
   Do not request organization Projects permissions from the ordinary metadata
   token or retry inaccessible Projects during unrelated operations.
   If Project access is unavailable, report `Project pending` and continue
   delivery unless the user explicitly makes it a blocking requirement. Never
   report unverified Project membership or status as applied.
8. Emit a handoff with the PR URL and failed field if a required non-Project
   field cannot be verified. Report App publication and personal Project
   updates separately.

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

Do not publish review, comment, reply, or thread-resolution content as part of
shipping unless the user separately authorizes that publication.
