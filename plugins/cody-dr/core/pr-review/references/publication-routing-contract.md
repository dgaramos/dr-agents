# Publication routing

Apply this contract to every already-authorized GitHub publication: issues,
pull requests, metadata, reviews, comments, replies, and thread resolutions.
It selects the publishing account; it never authorizes an additional action.

1. Prefer the executing adapter's App for each operation. Use read-only
   repository/profile/workflow discovery to determine whether its publisher is
   configured and usable. A missing profile is not evidence of App absence:
   also inspect the adapter's documented workflow names and repository guidance.
   For workflow publishers, use `core/pr-review/scripts/select-publisher.sh`
   with the repository and documented workflow path. Successful enumeration
   proving that workflow absent or disabled permits fallback; an active
   workflow must be dispatched as the App. Do not skip it because installation
   or secret availability could not be inspected. Do not install
   an App, request new credentials, or require a profile just to proceed.
2. Only when evidence proves the App operation unavailable, use the authenticated `gh`
   account as a personal fallback unless the user or repository explicitly
   requires App-only publication. The authorization for the requested action
   covers this fallback; do not add a second confirmation. Resolve the personal
   actor with `gh api user --jq .login` in the local personal-authentication
   context, never with an App installation token. Announce the fallback and
   reason before writing, and identify its actual actor in the result.
   Record the repository, operation, publisher checked, and observed evidence.
   Permission errors, failed discovery, timeouts, and assumptions from another
   repository are unknown availability, not fallback conditions. Select the
   route independently for each operation; a personal issue fallback does not
   authorize bypassing an available App for PRs, metadata, or reviews.
3. If no usable account is authenticated, return the prepared output as
   `not published` with the missing prerequisite. Do not weaken verification
   or invent configuration to bypass the missing access.
4. A confirmed failure before any publication, such as token generation failing
   because the App is not installed, permits the same personal fallback.
   A timeout, ambiguous dispatch result, partial publication, or unexpected
   author/target does not. Inspect the workflow run and target state first.
   Reuse verified results and retry only operations proven not to have happened;
   never blindly duplicate issues, PRs, reviews, or replies under another actor.
5. Preserve identical content, target, and verification requirements on either
   route. Use structured `gh api` requests and body files. For ordinary issue
   and PR metadata, prefer REST endpoints so Project permissions are irrelevant.
   When falling back, verify against the actual authenticated account, not the
   adapter bot. Report the App operation's availability independently from the
   adapter's identity and capabilities.

Projects are separately routed by the shipping contract and may use a different
actor. The executing adapter's commit co-author remains its own bot identity
even when a personal account publishes the PR or authenticates the push.
