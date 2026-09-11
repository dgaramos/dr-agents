# Changelog

All notable changes to this catalog are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.33] - 2026-09-11

### Added

- A seventh central publisher definition,
  `.github/workflows/reusable-publish-issue-comment.yml`, giving both Apps a
  route for commenting on an issue. The six existing definitions covered issue
  creation and update, pull request creation, pull request metadata, review
  submission, thread replies, and thread resolution; commenting had no route at
  all, which forced the evidence comment on #260 out under a personal account.
- `comment-issue` publisher stubs for both agents, and the matching installed
  templates.

### Changed

- The publisher smoke test now exercises the issue-comment route against the
  permanent `smoke-target` issue; the reaper deletes the comments it leaves. A
  GitHub App cannot delete an issue but can delete a comment on one, so this
  needs no additional disposable target.
- Stub surface bumped to `0.1.33`. Reinstall consumer stubs after the
  `workflows-v1` promotion.

### Unchanged, deliberately

- The `publisher definition release` marker stays at `3` and
  `minimum_stub_version` at `0.1.31`. Adding a definition does not change what
  the existing six do, and bumping either would make the marker lie about them.

## [0.1.15] - 2026-08-29

### Added

- Portable spec-driven development contracts, profile-declared external spec
  resolution, and equivalent Cody DR and Claudio DR entrypoints.

### Changed

- `execute-issue` now formally completes
  `start-issue → plan-implementation → implement-issue → ship-issue`; the
  shipping phase runs final validation, applies verified profile metadata, and
  emits its own output block before execution completes.
- Standalone `ship-issue` retains its explicit approval requirement, while an
  approved `execute-issue` lifecycle needs no second shipping confirmation.
- Updated Cody DR and Claudio DR to version `0.1.25`; reinstall or update the
  selected plugin after refreshing its marketplace source.

## [0.1.9] - 2026-08-24

### Changed

- Findings replies and thread resolutions now prefer and verify the configured
  reviewer App, with an explicitly authorized authenticated personal-account
  fallback only when the requested App operation is unavailable before
  dispatch. Failed App publication or verification never falls back silently.
- Updated Cody DR and Claudio DR to version `0.1.9`; reinstall or update the
  selected plugin after refreshing its marketplace source.

## [0.2.0] - 2026-08-22

### Added

- Canonical portable review contracts and equivalent Cody DR and Claudio DR
  adapters.
- Portable findings handling, issue authoring, and issue-to-change lifecycle
  skills.
- Consumer profile support and documented publisher dispatch boundaries.

### Changed

- Consolidated adapter behavior around the portable core contracts.

## [0.1.0] - 2026-08-20

### Added

- Initial catalog layout for core contracts, adapters, profiles, and examples.
- Cody DR and Claudio DR review plugins and the initial PR quality gate.
