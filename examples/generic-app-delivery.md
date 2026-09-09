# App delivery with an optional personal Project

An example repository declares an App `create-pr` publisher and an
`apply-pr-metadata` publisher. Its issue has one label and an assignee, no
milestone, and a user-owned Project. The user allows Project updates via local
`gh` authentication.

The executing adapter stages its changes and passes a message file to its
commit helper. The resulting commit preserves human co-authors and includes
exactly the executing adapter's co-author trailer. The helper does not change
the Git author or cryptographic signing configuration.

After pushing, the adapter dispatches its own App's PR publisher and verifies
the author and target. It applies labels and assignee through REST with the
App token. No milestone is invented and no Project data is requested here.
The local account then adds the PR to the Project and verifies its status.
The report names the App as PR/metadata publisher and the local account as
Project updater. If Project access fails, the report says Project pending;
the verified PR remains delivered.

For an organization-owned Project, an optional separate App token can carry
organization Projects write permission. Failure to obtain that permission
does not prevent the ordinary metadata token from working.

## Repository without a profile

The adapter still checks its documented workflow paths. Successful workflow
enumeration finds an active App PR publisher: select the App, even though no
profile exists. Do not select the personal account for convenience.

In a second repository, successful enumeration proves that publisher absent.
The already-authorized PR creation uses the existing authenticated `gh`
account, announces the reason, and verifies the actual personal author. The
commit co-author remains the executing adapter. Select metadata's route
separately; an available metadata App publisher must still be used.

If workflow discovery instead returns 403 or times out, availability is unknown.
Do not infer that the App is missing or publish personally. Likewise, inspect
an uncertain publication result before retrying. Only proven absence or a
confirmed pre-publication setup failure permits the fallback.
