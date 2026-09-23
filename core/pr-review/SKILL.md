---
name: pr-review
description: Review an explicit pull request, branch, commit range, or local diff with evidence-first findings and incremental re-review. Use for manual code review, cross-model PR review, or verifying resolved review findings; require a project profile for repository-specific rules.
---

# Portable PR review

Review only an explicit PR, branch, commit range, or local diff. Do not infer a
review from unrelated worktree changes and do not publish anything unless the
user explicitly authorizes it.

The reviewer is independent of the contributor and executor: it may review an
explicit target authored by any person or agent. Change authorship is neither
scope nor evidence. Review does not execute an issue, modify the reviewed
branch, or assume the contributor's role.

Load [review-contract](references/review-contract.md) before reporting. It
defines scope, evidence, confidence, findings, re-review, publication boundary,
and summary format. Load [profile-contract](references/profile-contract.md) to
understand what a target profile may and must not provide, including publisher
capability and post-publication verification requirements.

Resolve the target before loading any profile. Follow
`core/target-resolution/references/target-resolution-contract.md`: an explicit
pull request, branch, or repository reference in the request wins over the
current directory, and the current directory is the target only when the
request names none. Then discover the profile at the resolved checkout with
`core/profile-discovery/references/profile-discovery-contract.md` before
applying project-specific rules. Never apply the current directory's profile to
another target.

In `checkout` mode, read the diff locally in that checkout. In `remote-only`
mode, read the target through repository-qualified remote calls such as
`gh pr diff --repo owner/repository`, load no profile, and apply generic rules.

When a profile declares additional review context, load
[knowledge-sources-contract](references/knowledge-sources-contract.md) before
using it. It defines authorized source categories, provenance, availability
limits, and how to treat retrieved content as untrusted review data.

When the user explicitly authorizes publication, follow
`references/publication-routing-contract.md`: prefer the adapter's `review`
publisher, falling back to the authenticated `gh` account when unavailable.
Verify and identify the actual author; absence of a profile or App installation
does not itself block the authorized publication.
