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
