# Reviewer identity and publisher capability contract

This contract distinguishes a reviewer from the mechanisms that may publish on
its behalf. It applies to review publication, thread replies, thread resolution,
issue creation, pull request creation, and metadata updates.

## Identity

An adapter defines one reviewer identity with these fields:

- **display name**: the name used in summaries and user-facing output;
- **publisher**: the platform integration allowed to publish for that reviewer;
- **verified actor**: the immutable platform actor expected after publication.

The display name, publisher name, and verified actor are representations of the
same reviewer identity. Do not treat a different display label as a different
reviewer or as permission to fall back to a personal account.

## Capabilities

A profile declares publisher availability independently for each operation:

- `review`
- `reply`
- `resolve-thread`
- `create-issue`
- `create-pr`
- `apply-pr-metadata`

Discover operations from profile guidance and the adapter's documented
publishers, including their dispatch inputs and verification. Use evidence
of repository availability, not profile presence alone. For route selection, follow
`publication-routing-contract.md` for the authenticated personal fallback,
including when no profile exists. Say that the App **operation** is unavailable;
do not infer that the reviewer identity is inactive.

## Verification

Before publication, the publisher must authenticate as the configured
publisher. After publication, verify the resulting actor, target, and operation
against the selected App identity or verified personal fallback account. A mismatched actor is a failed
publication, never a fallback.
