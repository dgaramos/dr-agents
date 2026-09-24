# Dogfood: cross-repository target resolution from the catalog

Recorded evidence for dr-agents#338 (T11 checkpoint of epic #314), run on
2026-09-23 with the current working directory in this catalog and
`dgaramos/dr-specs` as the target.

This is a record of one live run, not a test that re-executes. The executable
covers are `tests/test_resolve_target.sh`, `tests/test_remote_write.sh` and
`tests/test_target_adoption.sh`; what they cannot cover is whether the contract
holds against a real repository and a real GitHub App, which is what this run
established.

## Why the search roots were set explicitly

`DR_AGENTS_REPO_ROOTS` was unset in the invoking environment. Per RF-03 an
unset variable falls back to the parent of the current repository —
`/Users/dgaramos/dev` — which already contains the `dr-specs` checkout. Left
unset, scenario (b) would have resolved to `checkout` mode and reported AC-06
satisfied without ever exercising the remote-only path. The variable is
therefore set deliberately in both scenarios below.

## (a) Checkout in a sibling root — AC-05

`DR_AGENTS_REPO_ROOTS=/Users/dgaramos/dev`, target `dgaramos/dr-specs` PR #31.

```console
$ bash core/target-resolution/scripts/resolve-target.sh https://github.com/dgaramos/dr-specs/pull/31
{"target":"dgaramos/dr-specs","host":"github.com","source":"explicit","reference":{"kind":"pr","number":31},"checkout":"/Users/dgaramos/dev/dr-specs","checkout_evidence":"root-scan:/Users/dgaramos/dev","mode":"checkout"}

$ bash core/profile-discovery/scripts/discover-project-profile.sh --root /Users/dgaramos/dev/dr-specs
/Users/dgaramos/dev/dr-specs/.dr-agents/dr-specs/PROFILE.md
```

The checkout was selected by normalized `origin`
(`git@github.com:dgaramos/dr-specs.git`), reported as
`checkout_evidence: root-scan:/Users/dgaramos/dev` — not by directory name.
Repository reads ran inside the resolved checkout
(`git -C /Users/dgaramos/dev/dr-specs diff --stat origin/main...f21c8ec`,
four files, 291 insertions).

Summary lines produced:

```md
**Target:** dgaramos/dr-specs (checkout: /Users/dgaramos/dev/dr-specs)
**Profile:** dr-specs (/Users/dgaramos/dev/dr-specs/.dr-agents/dr-specs/PROFILE.md)
```

The profile reported is the target's own, not this catalog's.

## (b) Checkout outside the search roots — AC-06

`DR_AGENTS_REPO_ROOTS=<empty directory>`, same target and PR. The `dr-specs`
checkout still existed on disk at the same path; it was simply not under any
configured root.

```console
$ bash core/target-resolution/scripts/resolve-target.sh https://github.com/dgaramos/dr-specs/pull/31
{"target":"dgaramos/dr-specs","host":"github.com","source":"explicit","reference":{"kind":"pr","number":31},"checkout":null,"checkout_evidence":"none","mode":"remote-only"}
```

No profile was discovered, because `remote-only` loads none. Every read was
repository-qualified:

```console
$ gh pr view 31 --repo dgaramos/dr-specs --json number,headRefName,baseRefName
pr=31 head=feat/change-discipline-spec base=main
$ gh api repos/dgaramos/dr-specs/pulls/31/files --jq '.[].filename'
specs/dr-agents/change-discipline/design.md
specs/dr-agents/change-discipline/requirements.md
specs/dr-agents/change-discipline/tasks.md
specs/dr-agents/index.md
```

Summary lines produced:

```md
**Target:** dgaramos/dr-specs (remote-only)
**Profile:** none (remote-only)
```

## (c) Authorized remote write and App publication — AC-09, AC-13

Explicitly authorized by the user in the invoking prompt. This was the first
run of `remote-write.sh` against a real repository; every prior exercise used a
fake `gh`.

Target resolved for a spec write:

```console
$ bash core/target-resolution/scripts/resolve-target.sh --from-specs-repository dgaramos/dr-specs
{"target":"dgaramos/dr-specs","host":"github.com","source":"specs-repository","reference":{"kind":"repo","number":null},"checkout":null,"checkout_evidence":"none","mode":"remote-only"}
```

`main` head captured before the write: `2d41f42251320aefe4496c8cedd78261822a7ba0`.
The new ref was confirmed absent (HTTP 404) beforehand.

```console
$ bash core/target-resolution/scripts/remote-write.sh dgaramos/dr-specs main \
    test/target-resolution-dogfood-338 manifest.json message.txt
{"commit":"37d49843489bcf2660227f65c14610ac89229348","ref":"refs/heads/test/target-resolution-dogfood-338","files":3}
```

The exit status was not trusted on its own. The commit was verified
independently through the API:

```console
$ gh api repos/dgaramos/dr-specs/commits/37d4984 --jq '{parents,files}'
parents: ["2d41f42251320aefe4496c8cedd78261822a7ba0"]
files:   specs/dr-agents/target-resolution-dogfood/design.md        (added)
         specs/dr-agents/target-resolution-dogfood/requirements.md  (added)
         specs/dr-agents/target-resolution-dogfood/tasks.md         (added)
```

- **Ancestry:** the commit's sole parent is exactly the `main` head captured
  before the run.
- **Scope:** three files, all `added`, all inside the manifest's directory. No
  path outside the manifest was touched.
- **Message:** the commit message is byte-for-byte identical to the message
  file (`diff` reported no difference).
- **Isolation:** `main` still pointed at `2d41f42` after the write.

No `--author` or `--committer` was passed, so GitHub attributed the commit to
the authenticated account with the `claudio-dr[bot]` co-author trailer carried
in the message — the contract's documented default and the same authorship
shape this catalog uses for its own commits.

The two refusal paths were then exercised live, both of which create nothing:

```console
$ remote-write.sh ... test/target-resolution-dogfood-338 ...        # branch exists, no --update
remote-write: branch 'test/target-resolution-dogfood-338' already exists in dgaramos/dr-specs; pass --update to move it
$ remote-write.sh ... test/does-not-exist-338 ... --update          # branch absent, --update
remote-write: branch 'test/does-not-exist-338' does not exist in dgaramos/dr-specs; omit --update to create it
```

After both refusals the existing ref was unchanged and the absent ref was still
absent.

Publication used `ship-change`'s `remote-only` entry point: the branch was
already pushed, so no checkout was reconstructed, no commit was produced by the
shipping flow, and the final gate was `not applicable (remote-only: validated
by the authorized write)`. The publisher was selected against the resolved
target:

```console
$ bash core/pr-review/scripts/select-publisher.sh dgaramos/dr-specs .github/workflows/publish-claudio-pr.yml
{"route":"app","workflow":".github/workflows/publish-claudio-pr.yml","reason":"matching workflow is active; dispatch App publisher"}

$ gh workflow run publish-claudio-pr.yml --repo dgaramos/dr-specs -F body=@body.md ...
https://github.com/dgaramos/dr-specs/actions/runs/35944196275   # completed success
```

Verification from the issue:

```console
$ gh api repos/dgaramos/dr-specs/pulls/32 --jq '.user.login + " " + .head.ref + " " + .base.repo.full_name'
claudio-dr[bot] test/target-resolution-dogfood-338 dgaramos/dr-specs
```

The PR belongs to the target repository, not to the catalog the agent was
running in, and its verified author is the adapter bot. The target's
`validate-specs` check passed on the written trio.

**Cleanup.** dr-specs#32 was closed without merging and its branch deleted:
`state=CLOSED merged=never`, and `refs/heads/test/target-resolution-dogfood-338`
returns HTTP 404. `main` remained at `2d41f42`, and a full listing of
`refs/heads` afterwards showed no leftover test ref.

## (d) Dirty working tree — AC-14

The `dr-specs` checkout was clean beforehand (`git status --porcelain` empty),
on branch `feat/change-discipline-spec` at `f21c8ec`. One untracked scratch file
was added, and the checkout-mode mutation gate was run:

```console
$ git -C /Users/dgaramos/dev/dr-specs status --porcelain
?? .dogfood-338-scratch.txt
$ git -C /Users/dgaramos/dev/dr-specs rev-parse --abbrev-ref HEAD
feat/change-discipline-spec
```

The flow stopped with a handoff reporting
`Checkout state: dirty: .dogfood-338-scratch.txt`. Nothing was stashed, reset,
checked out or committed: `HEAD` was still `f21c8ec` afterwards, unchanged from
before the gate. The scratch file was then removed and the tree confirmed clean
again.

Both conditions the gate gates on were in fact present — the tree was dirty and
the branch was not a working branch this flow had created — and either alone is
sufficient to stop.

## (e) A successful `--update` — ancestry from the branch head

Authorized as a follow-up on the same branch. This is the path the #402 fix
changed: before it, the second write parented from `base_sha`, which made every
repeat write a non-fast-forward. It had never run against a real repository.

`main` head before the run: `2d41f42251320aefe4496c8cedd78261822a7ba0`. The
branch was confirmed absent (HTTP 404).

```console
$ remote-write.sh dgaramos/dr-specs main test/target-resolution-update-338 m1.json msg1.txt
{"commit":"708f46ebc75f33bf16790dada56a7df5f2ef33b9","ref":"refs/heads/test/target-resolution-update-338","files":1}

$ remote-write.sh dgaramos/dr-specs main test/target-resolution-update-338 m2.json msg2.txt --update
{"commit":"c558fa834dacced889d4bf2cbbcdab5d9c4b1d4c","ref":"refs/heads/test/target-resolution-update-338","files":2}
```

Verified through the API, independently of both exit statuses:

```console
$ gh api repos/dgaramos/dr-specs/commits/708f46e --jq '[.parents[].sha]'
["2d41f42251320aefe4496c8cedd78261822a7ba0"]          # first write parents from the base

$ gh api repos/dgaramos/dr-specs/commits/c558fa8 --jq '{parents,files}'
parents: ["708f46ebc75f33bf16790dada56a7df5f2ef33b9"]  # second parents from the BRANCH head
files:   specs/dr-agents/target-resolution-update-probe/probe.md   (modified)
         specs/dr-agents/target-resolution-update-probe/probe2.md  (added)

$ gh api repos/dgaramos/dr-specs/git/ref/heads/test/target-resolution-update-338 --jq .object.sha
c558fa834dacced889d4bf2cbbcdab5d9c4b1d4c

$ gh api repos/dgaramos/dr-specs/compare/708f46e...c558fa8 --jq '{status,ahead_by,behind_by}'
{"status":"ahead","ahead":1,"behind":0}
```

- The second commit's **sole parent is the first commit**, not the base. This is
  exactly what #402 fixed.
- `probe.md` is reported `modified`, not `added` — the second tree was built on
  the *branch's* tree, so the earlier write's content was carried forward rather
  than replaced.
- `behind_by: 0` makes the move a fast-forward, which is what lets the script's
  `{sha, force:false}` ref update (`remote-write.sh:208`) succeed at all. A
  non-fast-forward would have been rejected by GitHub rather than silently
  forced.
- `main` was still at `2d41f42` afterwards.

The ref was then deleted; a re-read returns HTTP 404.

## (f) A full spec-authoring manifest

`core/spec/references/spec-contract.md:161` requires the authoring manifest to
carry the three trio files *and* the updated `index.md` in one commit. Scenario
(c) exercised `remote-write.sh` as a generic writer; this exercises the
composition rule that belongs to the caller.

The manifest declared four paths, with `index.md` taken from the current `main`
content and the new slug registered under `## Draft`:

```console
$ jq -r '.[].path' manifest.json
specs/dr-agents/target-resolution-manifest-probe/requirements.md
specs/dr-agents/target-resolution-manifest-probe/design.md
specs/dr-agents/target-resolution-manifest-probe/tasks.md
specs/dr-agents/index.md

$ remote-write.sh dgaramos/dr-specs main test/target-resolution-manifest-338 manifest.json msg.txt
{"commit":"3ed8324ccddab3f9a50afb85228e54545101f496","ref":"refs/heads/test/target-resolution-manifest-338","files":4}
```

Verified through the API:

```console
$ gh api repos/dgaramos/dr-specs/commits/3ed8324 --jq '{parents,files}'
parents: ["2d41f42251320aefe4496c8cedd78261822a7ba0"]
files:   specs/dr-agents/index.md                                         (modified)
         specs/dr-agents/target-resolution-manifest-probe/design.md       (added)
         specs/dr-agents/target-resolution-manifest-probe/requirements.md (added)
         specs/dr-agents/target-resolution-manifest-probe/tasks.md        (added)
```

- All four declared paths are in the commit's tree.
- `index.md` already existed, and it is reported **`modified`**, not `added` —
  the existing file was updated in place rather than replaced by a fresh blob at
  the same path.
- The registration is present on the branch:
  `- `target-resolution-manifest-probe` — draft (artefato de teste de dr-agents#338)`.
- Nothing else in the repository was disturbed: the branch tree holds 94 blobs
  against `main`'s 91 — exactly the three new trio files, with `index.md`
  updated rather than duplicated.
- `main` was still at `2d41f42` afterwards.

The ref was then deleted; a re-read returns HTTP 404.

## Cleanup of the follow-up scenarios

Neither (e) nor (f) opened a pull request — both test manifest and ancestry
behavior, which publication does not bear on, and (c) already recorded the
publication path end to end. Both branches were deleted directly.

```console
$ gh api repos/dgaramos/dr-specs/git/refs/heads --jq '[.[].ref]|map(select(test("test/")))'
[]
$ gh api repos/dgaramos/dr-specs/git/ref/heads/main --jq .object.sha
2d41f42251320aefe4496c8cedd78261822a7ba0
```

No test ref remains in the repository, `main` is unmoved from where it stood
before any scenario ran, and the only pull request any of this created —
dr-specs#32 — is closed and unmerged.

## Outcome

No defect was found in any of the six scenarios. Every claim the contract makes
about `remote-write.sh` — ordering of the fail-closed pre-check, ancestry from
the base head, ancestry from the branch head under `--update`, exact manifest
scope, byte-for-byte message, and refusal symmetry around `--update` — held on
its first contact with a real repository and a real App.

Both gaps this document originally recorded are now closed by live evidence:

- The **`--update` ancestry path** was left covered only by
  `tests/test_remote_write.sh` and by its refusal direction. Scenario (e)
  exercised it successfully against a real repository: the second commit's sole
  parent is the first commit, the earlier file came through as `modified`
  rather than re-added, and the ref move was a fast-forward
  (`behind_by: 0`) accepted under `force: false`. This is the path that #402
  fixed, and it now has real evidence rather than a fake `gh`.
- The **full spec-authoring manifest** — three trio files plus the updated
  `index.md` in one commit, per `core/spec/references/spec-contract.md:161` —
  was never run live. Scenario (f) ran it: all four declared paths are in the
  commit's tree, `index.md` is `modified` rather than `added`, and the blob
  count moved from 91 to 94, so nothing outside the manifest was disturbed.

AC-13 as dr-agents#338 states it — the PR belongs to the specs repository and
its verified author is the adapter bot — is satisfied by scenario (c)
independently of manifest composition, and both of its conjuncts are recorded
there. Scenarios (e) and (f) extend the evidence beyond what #338 required;
they do not change what AC-13 asserts.

Nothing in this run produced a code change. Everything recorded here is
evidence about behavior that already shipped.
