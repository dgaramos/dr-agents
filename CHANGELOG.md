# Changelog

All notable changes to this catalog are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.42] - 2026-09-25

Both adapters now expose machine-readable surface metadata for agents and
skills. Reinstall to make the declarations available to catalog consumers.

### Changed

- Agent and skill frontmatter now declares visibility, maximum effects, and
  authorization gates from the shared surface-metadata contract.
- `bin/check` validates the declarations and enforces cross-adapter parity.
- The designer entrypoints advertise their publishing reach because they can
  route an authorized request through `design-and-author`.
- Both plugin manifests, marketplace entries, and publisher stub markers now
  carry `0.1.42`.

## [0.1.41] - 2026-09-24

One adapter change and the release that carries it. Reinstall to pick up the
change-discipline contract that `0.1.40` bundled without a version signal.

### Changed

- Both adapters' `implement-issue` and `handle-pr-findings` skills now follow
  `core/issue-workflow/references/change-discipline-contract.md` by path, so
  Claudio DR and Cody DR constrain the shape of a diff identically. The rules
  stay in the core contract; the adapters carry only the reference.
- `bin/check` gained a parity loop over both skill names and both adapter
  prefixes. Dropping the reference from either adapter now fails with
  `parity: <skill> does not reference change-discipline-contract.md`.
- Stub surface bumped to `0.1.41`. Reinstall consumer stubs.

### Fixed

- `0.1.40` shipped the new change-discipline contract into both installable
  plugin trees while leaving both manifests and marketplace entries at
  `0.1.40`, so installed copies could differ in content under an unchanged
  version. Both plugins, both marketplace entries, and every publisher stub
  marker now carry `0.1.41`.

## [0.1.40] - 2026-09-24

Two epics closed in this range: #313 (authorized review publication) and #314
(target resolution). Both are user-visible in the adapters, so reinstall after
upgrading.

### Added

- `core/target-resolution/`: a portable contract, `resolve-target.sh`, and
  `remote-write.sh`. Every flow now resolves *which repository* it is acting on
  before discovering a profile — an explicit target (PR or issue URL,
  `owner/repo`, or the resolved `SPECS_REPOSITORY`) wins over the current
  directory, checkouts are matched by normalized `origin` and never by directory
  name, and a flow with no checkout declares `remote-only` instead of guessing.
- `remote-write.sh` creates or updates a branch through the git-data API with no
  checkout at all: blobs, tree, commit, ref. Optional `--author`/`--committer`
  make authorship chosen rather than inherited from whichever account is
  authenticated.
- Four portable review-publication scripts — load threads, validate the
  manifest, dispatch, verify — so an authorized review publishes in one pass and
  is checked afterwards rather than assumed.
- `bin/check` gained four guards derived from the tree, not from a list: adopter
  parity between the two adapters, a guard against any surface discovering the
  profile from the current directory, the RF-11 summary-order rule, and a
  portability grep over `core/target-resolution`.
- `docs/dogfood-target-resolution.md` records a live cross-repository run
  against the specs repository: checkout-mode resolution, `remote-only` reads,
  an authorized remote write published through the target's own App, a
  dirty-tree handoff, a successful `--update` parenting from the branch head,
  and a full spec-authoring manifest.

### Changed

- Every adopting summary now leads with `**Target:**` then `**Profile:**`
  (RF-11), including the review, re-review, issue-draft, ship, start and spec
  blocks. `verify-review-surface.sh` enforces the order rather than the previous
  verdict-first shape.
- `ship-change` opens the pull request in the *resolved* target through that
  repository's App publisher, and gained a `remote-only` entry point that ships
  no commits of its own.
- Mutating flows stop before their first write when the resolved checkout is
  dirty or on an unexpected branch, reporting `Checkout state:` and handing back.
- The spec flow proposes a canonical path when it is not authorized to write,
  and writes the trio plus the project `index.md` when it is.
- Review summaries are scannable: verdict and next step first, size-gated, with
  a defined thread-reply anatomy and an implementer role marker.
- Stub surface bumped to `0.1.40`. Reinstall consumer stubs after the
  `workflows-v1` promotion.

### Fixed

- `remote-write.sh --update` parented every repeat write from the base branch,
  making each one a sibling of the branch head and a guaranteed
  non-fast-forward rejection. It now parents from the existing head and builds
  on that tree.
- The same script's branch pre-check treated *every* failed ref lookup as "the
  branch is absent", so an auth, rate-limit or network error fell through to the
  create path and uploaded objects before discovering the ref existed. Only a
  404 now means absent; anything else refuses to write.
- The publisher PR actor is reported and enforced: an agent delivery branch
  whose pull request was opened by a personal account is caught rather than
  passing unnoticed.
- `bin/install` derives its managed stub set from the catalog instead of a
  hand-kept list, and rejects mutually exclusive mode flags.

### Known gaps

- The adapter Apps can publish reviews and thread replies but cannot call
  `resolveReviewThread` (`Resource not accessible by integration`), so
  resolutions — named in #313's goal alongside findings and replies — still
  require a personal account. This is a publisher permission, not catalog code.
- The catalog `v0.1.x` tag line lapsed after `v0.1.15`; the `0.1.33` entry above
  was never tagged. This release resumes it. `workflows-v1` is a separate,
  deliberately moving tag and was unaffected.

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
