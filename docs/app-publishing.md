# App publication and commit attribution

Both adapters provide `create-pr`. A publisher installed in a consumer
repository is a thin `workflow_dispatch` stub: it carries the input names and
nothing else, and calls the central definition in this catalog, which checks
this repository out at the ref the stub names and runs the publication scripts
from there. No publication script is copied into a consumer.

Update the plugin, run `agents install --workflows` in each consumer
repository, and commit the stubs to that repository's default branch before
dispatching. A repository migrated from the earlier vendored layout may still
carry `.github/scripts/agent-workflows/`; nothing reads it, the installer
reports it and will not delete it, and it is safe to remove by hand. See
[workflow-releases.md](workflow-releases.md) for the release scheme that
governs which definition a stub executes.

App-first routing applies even without a profile. The adapter checks its
documented workflow paths; `select-publisher.sh` selects an active workflow
as the App route. Only successful discovery proving it absent or disabled
permits the authenticated personal fallback. Lookup errors or unknown
availability do not. A verified token-creation failure before publication can
also permit fallback; ambiguous or partial outcomes must be inspected first.
The agent announces the evidence and verifies the actual publishing account.
Selecting a fallback for one operation does not change the others' routing.

Declare the matching `create-pr` publisher in each project profile. Its inputs
are `title`, completed Markdown `body`, `head_branch`, and `base_branch`. It
uses Pull requests write permission and verifies the App author and PR target.
An identical retry reuses the existing PR. Existing PRs by a different author
cannot be reassigned to the App. Ordinary metadata uses REST to avoid the
implicit Project queries made by some `gh pr` commands.

Projects remain a separate capability. For a Project owned by the repository's
organization, the metadata workflow attempts a separate App installation token
with `permission-organization-projects: write`. The App installation must
actually have that grant; failure does not block the repository metadata token.
Projects belonging to another owner require separately configured access.

For user-owned Projects, use the authorized local `gh` account with Project
access and report its actor separately. Omit Project inputs from the App
dispatch. If access is unavailable, report Project pending without blocking
delivery unless the user explicitly requires it. GitHub recommends Apps for
organization Projects and personal tokens for user Projects; see
[Automating Projects using Actions](https://docs.github.com/en/issues/planning-and-tracking-with-projects/automating-your-project/automating-projects-using-actions).

For authorized commits, invoke the installed adapter's `scripts/commit.sh`
with a message file after staging the intended files. It preserves human
co-authors, replaces generic agent attribution, and verifies its own trailer.
The canonical bot emails include the numeric bot user ID, following
[GitHub's App committer example](https://github.com/actions/create-github-app-token#configure-git-cli-for-an-apps-bot-user).
The IDs were verified through the public users API: Cody DR `318732897` and
Claudio DR `318764128`.

Co-authorship, commit signing, and the account authenticating `git push` are
different. The helper preserves the user's author and signing configuration;
it does not claim a cryptographic App signature. Push continues to use the
profile's configured Git transport. Making the App the push actor requires an
App-authenticated transport with Contents write; workflow installation alone
does not configure local Git credentials. Historical commits are unchanged.
