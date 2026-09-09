# Project profile contract

A profile may define:

- project identity and supported branches;
- required context files and architecture boundaries;
- layer-specific review checklists;
- quality commands and known check limitations;
- risk axes and public-contract rules;
- reviewer identity and optional publisher capability. Load
  `core/pr-review/references/reviewer-identity-contract.md` when a profile
  defines either.
- knowledge sources by pointing to authorized local guidance, GitHub delivery
  context, official documentation, or optional MCP integrations. Load
  `core/pr-review/references/knowledge-sources-contract.md` before using them.

A profile must not:

- weaken the core evidence threshold or explicit-publication boundary;
- contain credentials, secrets, private keys, or installation tokens;
- make automatic review mandatory without an explicit workflow outside the core.
- copy private source content, credentials, or cloned target repositories into
  the catalog instead of declaring their location and purpose.

## Publisher capability contract

A profile that provides a publisher must document:

- **reviewer identity**: display name, publisher integration, and the verified
  platform actor; the three values represent one reviewer, as defined by the
  reviewer identity contract;

- **dispatch**: how to invoke the publisher (command, API call, or webhook) and
  what inputs it requires (event type, repository, PR number, review body,
  inline comments);
- **reply mode**: how to send a reply into an existing review thread (required
  if the adapter supports thread replies);
- **resolution mode**: how to resolve a review thread (required if the adapter
  supports thread resolution);
- **create-issue mode**: how to create a GitHub issue (repository, title, body,
  and profile-owned fields such as labels, assignees, milestone, and Projects);
  required if the adapter supports issue authoring via the publisher.
- **create-pr mode**: how to create a pull request as the adapter App, with
  title, completed body, pushed head branch, base branch, and actor verification.
- **apply-pr-metadata mode**: how to apply ordinary metadata using the App
  without querying Projects. Declare Projects separately, including owner type,
  available authentication, and whether an authorized personal fallback exists.

A profile that does not document a mode signals that the App operation is
unavailable. Apply `publication-routing-contract.md` for personal fallback;
the same rule applies when no profile exists.

### Personal fallback

Follow `publication-routing-contract.md`. An authorized operation uses the App
when available and the existing authenticated `gh` account otherwise, unless
the user or repository requires App-only publication. No extra approval is
needed just because an App or profile is absent. Verify the actual personal
actor and label the fallback. Inspect ambiguous or partial publication before
retrying; never treat a mismatched actor or target as successful publication.

### Post-publication verification

After every publisher action, the adapter must verify:

- **After publishing a review**: the resulting review's author matches the
  expected reviewer identity and the event matches the authorized action
  (`REQUEST_CHANGES`, `COMMENT`, or `APPROVE`).
- **After replying to a thread**: the reply is authored by the expected reviewer
  in the intended thread, not as a separate review or personal comment.
- **After resolving a thread**: the expected reviewer resolved the intended
  thread; the thread state reflects resolution.
- **After creating an issue**: the created issue's author matches the configured
  reviewer bot identity and the issue number is recorded in the draft summary.

If verification fails, report the failure and do not mark the action as
published.
