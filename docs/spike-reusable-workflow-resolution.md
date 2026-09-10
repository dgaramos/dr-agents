# Spike: how a reusable workflow reaches catalog files

Measurement record for [#260](https://github.com/dgaramos/dr-agents/issues/260)
task T01, satisfying AC-01. The spike workflows that produced it were removed in
the same pull request; this document is the retained evidence.

## Question

Decision D2 chose a composite action as the mechanism for centralizing the
Claudio DR and Cody DR publishers. The spike validates that choice rather than
comparing alternatives: **can a composite action hosted in `dr-agents` read
files that exist only in `dr-agents`, when the reusable workflow that uses it is
resolved remotely, and is the called ref honored?**

## Contradiction condition, declared before measuring

The migration stops and the result is reported before any migration pull request
is opened if either holds:

- **M1 is false** — the composite action cannot read `dr-agents` files.
- **M2 shows the called ref is not honored** — the action resolves to the
  default branch regardless of the ref the caller named, which would make the
  `@v1` release scheme in D3 meaningless.

Neither occurred. D2 is confirmed.

## Method

A throwaway composite action at `.github/actions/spike-probe/` reported
`GITHUB_ACTION_PATH`, `GITHUB_WORKSPACE`, and the contents of the directory
three levels above the action. It probed for
`core/issue-workflow/references/plan-issue-contract.md`, a file present in
`dr-agents` and in none of the consumer repositories, and for a `REF-MARKER`
file whose content names the spike branch.

A reusable workflow with `on: workflow_call` used that action in two jobs — once
by full `owner/repo/path@ref` and once by local `./path` — and a caller workflow
invoked the reusable workflow by full `owner/repo/path@ref`, which is the same
remote resolution path a consumer repository uses.

## Results

Run [34501115856](https://github.com/dgaramos/dr-agents/actions/runs/34501115856):

```text
GITHUB_ACTION_PATH = /home/runner/work/_actions/dgaramos/dr-agents/260-feat/reusable-workflow-publishers/.github/actions/spike-probe
GITHUB_WORKSPACE   = /home/runner/work/dr-agents/dr-agents
resolved repo root = /home/runner/work/_actions/dgaramos/dr-agents/260-feat/reusable-workflow-publishers
M1  = TRUE   (sha256 71bc4fa0dd125cfaebdef6139f56ebfee67c19063a2972561e86feb45f08ae38)
M1b = FALSE  (file came from the action checkout only)
M2  : action root basename = reusable-workflow-publishers
M3  : marker = 260-feat/reusable-workflow-publishers
```

- **M1 — catalog files are readable.** The runner stages the entire action
  repository, so `${GITHUB_ACTION_PATH}/../../..` is the `dr-agents` repository
  root and every catalog file is readable from it.
- **M1b — the read is genuinely from the action checkout.** The caller workspace
  did not contain the probe file, because no `actions/checkout` ran. The file can
  only have come from the staged action repository.
- **M2 and M3 — the called ref is honored.** The staging path is keyed by the ref
  the caller named, and the marker file carries the spike branch rather than the
  default branch. A moving `@v1` tag will therefore select what consumers run,
  which is what D3 depends on.

## Three findings that change the migration

1. **A local `./` action path does not work inside a remotely resolved reusable
   workflow.** The job using `uses: ./.github/actions/spike-probe` failed with
   `Can't find 'action.yml' … under /home/runner/work/dr-agents/dr-agents/.github/actions/spike-probe`,
   because `./` resolves against the *caller's* workspace. The central definition
   must reference its composite action by full `owner/repo/path@ref`, and the ref
   must be kept in step with the release tag.

2. **A dangling symlink anywhere in the repository breaks action staging
   entirely.** The first spike run failed before reaching the probe:

   ```text
   Could not find file '…/_staging/dr-agents-<sha>/.claude/agents/cody-workflow.md'
   ```

   The runner stages the whole repository before resolving the action and aborts
   on the first unresolvable link. Two links left dangling by #163 made
   `dr-agents` unusable as an action repository. They are removed, and `bin/check`
   now fails on any dangling symlink.

3. **`workflow_dispatch` requires the workflow to exist on the default branch.**
   Dispatching the spike from the feature branch returned
   `HTTP 404: workflow spike-caller.yml not found on the default branch`. This is
   the empirical confirmation of why every consumer keeps a thin dispatch stub:
   the stub is irreducible, not a convenience.

---

# Round 2: can a reusable workflow derive its own ref?

A second measurement, recorded here rather than by rewriting the T01 record
above. It was prompted by a real failure, not by a hypothesis.

## What went wrong first

Run [34505697770](https://github.com/dgaramos/dr-agents/actions/runs/34505697770)
dispatched `publish-claudio-pr-metadata.yml` on `main` against PR #263 with the
metadata that pull request already carried. It failed:

```text
METADATA_HELPER: /core/issue-workflow/scripts/apply-pr-metadata.sh
bash: /core/issue-workflow/scripts/apply-pr-metadata.sh: No such file or directory
ERROR: core metadata step failed; labels/milestone/assignee may be incomplete
```

Nothing was mutated; the job died before any write.

**Cause: a version skew between the workflow and the action.** The stub calls
`reusable-publish-pr-metadata.yml@main`. That workflow reached its composite
action at the fixed ref `...catalog-scripts@workflows-v1`. So the workflow came
from `main` and the action came from the tag. `main` already had the `root`
output; the tag did not:

```console
$ git show workflows-v1:.github/actions/catalog-scripts/action.yml | grep -c 'root:'
0
$ grep -c 'root:' .github/actions/catalog-scripts/action.yml
1
```

An empty `root` produced the leading-slash path above.

**The skew was silent in four of five publishers.** Only
`reusable-publish-pr-metadata.yml` consumes `outputs.root`;
`reusable-publish-{pr,reply,resolve,review}.yml` consume only `outputs.path`,
which the stale action still provided. They would have stayed green against the
old action. The observed failure was luck, not the typical manifestation.
`reusable-publish-issue.yml` uses no composite action at all, so five call sites
are affected, not six.

The general consequence is worse than the bug: **`@main` dogfooded only the
workflow, never the action or the scripts**, which always came from the tag.
Promoting the tag realigns them once, and every later dogfooding run again
exercises a new workflow against an old action — the environment under test
stops representing production, which is the worst failure mode for a release
mechanism.

## Question

Can a reusable workflow, resolved remotely, derive the ref it was itself called
at, so that it can `actions/checkout` the catalog at that exact ref and make the
workflow and the scripts come from one commit by construction?

## Contradiction condition, declared before measuring

- **C1** — If neither `github.job_workflow_ref` nor `github.workflow_ref`
  reports the *called* workflow's own ref, the approach is impossible. Stop and
  report before opening any pull request.
- **C2** — If the value resolves on a branch but cannot be parsed into
  `(owner/repo, ref)` covering both `refs/heads/*` and `refs/tags/*`, it cannot
  survive tag promotion. Stop and report.
- **C3** — If `actions/checkout` at the derived ref does not yield a readable
  `core/issue-workflow/scripts/apply-pr-metadata.sh`, the mechanism does not
  replace the composite action. Stop and report.

## Method

T01 finding 3 rules out `workflow_dispatch` from a feature branch. Instead a
**push-triggered caller** on the feature branch called a probe reusable workflow
by full `owner/repo/path@ref`, which is the same remote resolution path a
consumer uses, without any commit to `main` and without touching the tag.

The probe reported `github.workflow_ref`, `github.job_workflow_ref`,
`github.workflow_sha`, `github.job_workflow_sha`, the complete list of
`GITHUB_*` environment variable names, and the `job_workflow_ref` claim of an
OIDC token. Only the two non-secret claims were read out of the token; the token
itself was never printed.

## Results

Run [34506407927](https://github.com/dgaramos/dr-agents/actions/runs/34506407927)
(expression context) and
[34506548071](https://github.com/dgaramos/dr-agents/actions/runs/34506548071)
(environment and OIDC):

```text
github.workflow_ref     = dgaramos/dr-agents/.github/workflows/spike-ref-caller.yml@refs/heads/260-fix/derive-catalog-ref
github.job_workflow_ref = (empty)
github.workflow_sha     = a3fc92a375e67d9e62a5e5f84ed9fe147e3621a4   (the caller's sha)
github.job_workflow_sha = (empty)

GITHUB_WORKFLOW_REF     = …/spike-ref-caller.yml@refs/heads/260-fix/derive-catalog-ref
GITHUB_JOB_WORKFLOW_REF = does not exist (full GITHUB_* name listing confirms)

OIDC job_workflow_ref   = dgaramos/dr-agents/.github/workflows/spike-ref-probe.yml@refs/heads/260-fix/derive-catalog-ref
OIDC workflow_ref       = dgaramos/dr-agents/.github/workflows/spike-ref-caller.yml@refs/heads/260-fix/derive-catalog-ref
```

- **`workflow_ref` names the caller, not the called workflow.** In this
  measurement the caller happens to sit on the same branch, so the ref looks
  correct; in production the caller is a consumer repository and the value would
  be, for example,
  `dgaramos/dotfiles/.github/workflows/publish-claudio-pr-metadata.yml@refs/heads/main`.
  Deriving a `dr-agents` ref from it is impossible.
- **`job_workflow_ref` is not exposed to the expression context or the
  environment.** It is empty in `github`, and no `GITHUB_JOB_WORKFLOW_REF`
  variable exists.
- **The OIDC token does carry the correct claim**, naming the probe workflow at
  the branch it was called at.

**C1 fired for the recommended mechanism.** The migration stops here, as
declared, and no pull request was opened.

## Consequence for the design

The only runtime source of the called ref is the OIDC token, and using it is not
free. Permissions cannot be escalated across the reusable-workflow boundary —
measured directly: the round-2 probe returned `startup_failure` until
`id-token: write` was added to the **caller**. Every consumer stub would
therefore have to grant `id-token: write`, and every publisher would mint an
identity token it needs for nothing else.

Two mechanisms remain, and the choice is a decision rather than a measurement:

1. **OIDC-derived ref.** No duplicated ref, but `id-token: write` in all twelve
   stubs of all four consumers, plus a token request and JWT decode in every
   publisher.
2. **Explicit `catalog_ref` input.** The stub already names the ref literally in
   `uses:`; it repeats it in `with:`, and `bin/check` asserts the two agree in
   both the catalog stubs (`@main`) and the installed templates
   (`@workflows-v1`). No new permission, no runtime derivation, and the same
   same-commit guarantee — enforced at check time instead of at run time.

Both cost one edit per stub. That edit is currently free: T06, T07 and T08 have
not run, so no consumer has been migrated yet. This is why the fix blocks them.

## Decision

**Option 2, the explicit `catalog_ref` input.** OIDC would buy a new permission
in twelve stubs across four repositories, and make every publisher mint an
identity token it uses for nothing else, all to resolve at run time something
that is static and checkable before anything runs. `catalog_ref` gives the same
same-commit guarantee with no new permission, and `bin/check` asserts that the
ref a stub calls and the ref it passes are identical. The composite action was
removed: `uses:` accepts no expressions, so any surviving action would
reintroduce the fixed ref this fix exists to remove.

The genuine proof of the mechanism remains a real dispatch on `main` after the
fix merges. Nothing in this record claims that proof.
