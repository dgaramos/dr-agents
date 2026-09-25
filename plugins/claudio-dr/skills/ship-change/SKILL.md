---
name: ship-change
description: Claudio DR prepares and publishes a pull request in the resolved target repository. Runs the final quality gate and opens the authorized PR.
visibility: internal
effects: [writes-workspace, publishes]
gates: [explicit-authorization]
---

# Claudio DR ship-change

Reviewer identity: **Claudio DR** (Claude App reviewer).

Load `core/issue-workflow/skills/ship-change/SKILL.md` and follow its
referenced contracts, including
`core/pr-review/references/publication-routing-contract.md`. Prefer the
`create-pr` App publisher without a second confirmation after an explicit
issue-execution request. Personal fallback requires evidence of unavailability.

Resolve the target first with
`core/target-resolution/references/target-resolution-contract.md`,
then discover its profile at the resolved checkout with
`core/profile-discovery/references/profile-discovery-contract.md`. Push from
that checkout with `git -C <checkout> push`.

Follow `core/issue-workflow/references/contribution-guidance-contract.md` to
apply PR-body and delivery-metadata guidance from `CONTRIBUTING.md`. A missing
file is not a blocker; surface any material conflict with the profile before
opening the PR.

Select `.github/workflows/publish-claudio-pr.yml` and
`.github/workflows/publish-claudio-pr-metadata.yml` against the resolved target
with `core/pr-review/scripts/select-publisher.sh` when no profile provides
different publishers, and dispatch each one qualified with `--repo <target>`.
Verify that the resulting PR belongs to the target and that its author is
Claudio DR's App, or announce and verify the personal actor selected by the
routing contract. Projects remain separate.
