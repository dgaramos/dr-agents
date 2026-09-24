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

## Outcome

No defect was found. Every claim the contract makes about `remote-write.sh` —
ordering of the fail-closed pre-check, ancestry from the base head, exact
manifest scope, byte-for-byte message, and refusal symmetry around `--update` —
held on its first contact with a real repository and a real App.

Not covered by this run: the `--update` ancestry path (parenting from an
existing branch head) was exercised only in its refusal direction, because the
authorization for this dogfood covered a single commit. A successful `--update`
against a real repository remains covered by `tests/test_remote_write.sh` alone.

Also not covered: a full spec-authoring manifest. Scenario (c) wrote the test
trio that dr-agents#338 task (c) specifies, exercising `remote-write.sh` as the
generic writer it is — ancestry, manifest scope, exact message, refusal
symmetry. It did not run the spec-authoring flow, whose manifest must carry the
three trio files *and* the updated `index.md`
(`core/spec/references/spec-contract.md:161`). That composition rule belongs to
the caller, not to the writer, and no live run has exercised it. AC-13 as
dr-agents#338 states it — the PR belongs to the specs repository and its
verified author is the adapter bot — is satisfied independently of manifest
composition, and both of its conjuncts are recorded above.
