---
name: ship-change
description: Cody DR prepares and publishes a pull request for a completed implementation. Runs the final quality gate and opens the authorized PR.
---

# Cody DR ship-change

Reviewer identity: **Cody DR** (Codex App reviewer).

Load `core/issue-workflow/skills/ship-change/SKILL.md` and follow its
referenced contracts, including
`core/pr-review/references/publication-routing-contract.md`. Prefer the
`create-pr` App publisher without a second confirmation after an explicit
issue-execution request. Personal fallback requires evidence of unavailability.

Discover the target profile first with
`core/profile-discovery/references/profile-discovery-contract.md`.

Follow `core/issue-workflow/references/contribution-guidance-contract.md` to
apply PR-body and delivery-metadata guidance from `CONTRIBUTING.md`. A missing
file is not a blocker; surface any material conflict with the profile before
opening the PR.

Discover `.github/workflows/publish-cody-pr.yml` and
`.github/workflows/publish-cody-pr-metadata.yml` when no profile provides
different publishers. Verify Cody DR's App result, or announce and verify
the personal actor selected by the routing contract. Projects remain separate.
