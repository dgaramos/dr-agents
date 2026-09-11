# Releasing the central publisher definition

The reusable publisher workflows in `.github/workflows/reusable-publish-*.yml`
are consumed by other repositories. They are released under their own moving tag,
**`workflows-v1`**, which is deliberately separate from the catalog's `v0.1.x`
version line: a patch release of the catalog must never move what four
repositories execute.

## Why a moving tag

Decision D3 of [#260](https://github.com/dgaramos/dr-agents/issues/260). A
pinned SHA in each consumer would reintroduce exactly the cost this migration
removes — the one-line fix in #258 needed four pull requests. With a moving tag,
a behavior fix reaches every consumer by promoting the tag, and a rollback is
repointing it, with no commit in any consumer.

The risk of a moving tag is breaking all consumers at once. It is mitigated by
dogfooding, below, and bounded by a rollback that touches only this repository.

## The caller supplies the ref

An earlier version of this document claimed that the internal
`...catalog-scripts@workflows-v1` ref was "stable rather than circular". **That
was wrong, and it caused a production failure.**

The reasoning only held at the moment of promotion. Between promotions the two
halves came from different commits: a stub calling `@main` got a workflow from
`main` and a composite action from the tag. Run
[34505697770](https://github.com/dgaramos/dr-agents/actions/runs/34505697770)
failed with `METADATA_HELPER: /core/issue-workflow/scripts/apply-pr-metadata.sh`
because the workflow on `main` read an output the tagged action did not define.

Worse than the bug: **`@main` dogfooded only the workflow.** The action and the
scripts always came from the tag, so the environment under test never
represented production — the exact property a release mechanism exists to
provide. And the skew was silent in four of the five affected publishers, which
consume only the action's `path` output; the one visible failure was luck.

A reusable workflow cannot fix this by deriving its own ref. That was measured,
not assumed (`docs/spike-reusable-workflow-resolution.md`, round 2):
`github.workflow_ref` names the **caller**, `github.job_workflow_ref` is exposed
to neither the expression context nor the environment, and only an OIDC token
carries the called ref — at the price of `id-token: write` in every consumer
stub. `uses:` accepts no expressions, so a composite action could never carry a
derived ref either. The composite action was therefore removed rather than
repaired.

**The stub passes the ref it calls.** Each reusable publisher declares a
required `catalog_ref` input and checks this repository out at it:

```yaml
    uses: dgaramos/dr-agents/.github/workflows/reusable-publish-pr.yml@workflows-v1
    with:
      catalog_ref: workflows-v1
```

`bin/check` asserts the two are **identical** in every stub, and that the
catalog's own stubs say `main` while the installed templates say `workflows-v1`.
The workflow and the scripts it runs now come from one commit by construction,
verified before anything executes rather than derived while it runs.

`reusable-publish-issue.yml` takes no `catalog_ref`: it is self-contained and
reads no catalog file, so a required input there would be one nothing consumes.

## Bootstrapping the tag

The promotion procedure below moves an existing tag. The first release has to
create one, and it cannot be skipped: an installed stub names `@workflows-v1` in
both `uses:` and `catalog_ref`, so until that ref resolves, no consumer
publisher runs at all. `workflows-v1` was created as an annotated tag at
`1b5efd3`, the merge of #262. It is deliberately behind `main` and must be
promoted after the ref fix merges.

## Publication scripts resolve inside the catalog

A reusable publisher checks this repository out at `catalog_ref` into
`.dr-agents-catalog`, and never checks the *caller* out. Every path a
publication step uses is addressed inside that directory. This is why
`.github/scripts/` stays in this repository: it is the source the publishers
run, not a leftover of the vendored copies.

The checkout is pinned to `actions/checkout@11d5960a326750d5838078e36cf38b85af677262`
(v4.4.0). It is the single pin AC-09 requires: one, in the central definition,
rather than one per consumer. A step validates `catalog_ref` before the checkout
and fails loudly when it is empty or malformed, so a misconfigured stub reports
that rather than a confusing "No such file" from a publication script.

The one script that reaches outside `.github/scripts/` is the metadata helper
under `core/`. `reusable-publish-pr-metadata.yml` takes a `metadata_helper`
input; when it is empty the checked-out catalog's own helper is used. A
consumer's locally installed helper can no longer be named by a caller-relative
path, because nothing checks the caller out.

## Which definition executed

`workflows-v1` is a moving tag, so the ref a run reports is the same string
before and after a promotion. The ref alone therefore cannot answer the one
question a promotion raises: did this run execute the new definition?

Every central definition answers it directly. Its first step — first, so the
answer survives a failure in any later step — writes to the step summary:

```text
- publisher definition release: `2`
```

`bin/check` requires all six definitions to carry the same value. Bump it in
the same change that alters what a publisher does, and never bump it in only
some of the six: a marker that disagrees with itself is worse than none.

This is the same norm the migration recorded for publication outcomes — a run
states what happened rather than leaving it to be inferred from an exit code.

## The smoke test

`.github/workflows/smoke-publishers.yml` dispatches the publishers for real
against a disposable target in this repository and asserts on what GitHub holds
afterwards. It exists because every defect the migration put into production was
correct as text and wrong as executed; `bin/check` caught none of them, and
three surfaced by accident (dr-agents#267).

It asserts **the resource and its author**, not the job's exit code. In
dr-agents#258 the reply publisher posted its comment and then exited 1, so exit
code and reality disagreed; a check reading only the exit status calls that a
clean failure and leaves a stray comment behind. The smoke test fails that case
*naming* the publisher whose resource exists over a red job.

It does not read the typed publication outcome from the step summary, because
that vocabulary currently exists in exactly one of the six definitions —
`reusable-publish-issue.yml`. The other five write only the release marker and
the catalog ref to the summary, which is why the `GITHUB_STEP_SUMMARY`
assertion in `bin/check` passes over all six without noticing. Extending the
vocabulary to the other five is tracked separately; the smoke test lands first
so that the detector is proven against the publishers as they are before it is
used to certify a change to them.

### Where it sits

- **push to `main`** — one agent, the full six-publisher chain. This is the
  automated counterpart of step 3 below, which until now rested on an operator
  remembering to look.
- **`workflow_dispatch`** — both agents, and additionally a job pinned at
  `@workflows-v1`, which is the only way to observe that the tag resolves and
  serves the definitions consumers call. `uses:` accepts no expressions, so the
  ref under test cannot be an input; it is a separate, statically pinned job.
- **push of the `workflows-v1` tag** — both agents, immediately after a
  promotion.

Force-moving an existing tag does fire a `push` event, and the run executes at
the tag's new commit. That was measured with a throwaway probe tag rather than
assumed. One consequence follows from it: a tag-triggered run executes the
workflow file **as it exists at the tag**, so this trigger stays inert until a
promotion first carries the file onto `workflows-v1`.

### What it leaves behind

The disposable pull request targets a permanent `smoke-base` branch, never
`main`, so it costs no CI run and is not subject to the adapter co-author rule.
The issue publisher updates one permanent `smoke-target` issue per agent rather
than creating one per run, because an App cannot delete an issue. When that
target does not exist yet, the run creates it through the issue publisher
itself: `reusable-publish-issue.yml` treats an empty `issue_number` as create
and a populated one as update, so the first run exercises the creation path of
the definition under test and every later run the update path. The target is
therefore authored by the App, which is what discovery by author requires, and
there is no manual bootstrap step. The `smoke-target` label is re-asserted on
every run, so a removed label heals itself rather than becoming a second thing
to fix by hand.

Cleanup runs at the end of the run, and a reaper runs at the **start** of every
run as well. The second is what matters: a cleanup job cannot run for a run that
was cancelled or whose runner died. If a run dies between pushing the branch and
cleaning up, an orphaned `smoke/publishers-<run_id>` branch and an open pull
request against `smoke-base` survive until the next run sweeps them. Anything
the reaper cannot remove is named in the run output and the step summary rather
than failing the run, so a stranded leftover never masks the dispatch result.

## Promotion procedure

1. Merge the change to `main`.
2. Dogfood it: this repository's own stubs point at `@main`, not at the tag, so
   every publisher here exercises the new definition before any consumer sees
   it. `bin/check` enforces both halves of that split — the twelve stubs under
   `.github/workflows/` must pin `@main` and the twelve templates under
   `plugins/*/workflows/` must pin `@workflows-v1` — so the two refs cannot be
   swapped by accident.
3. Confirm the publishers of this repository ran green. The push to `main` in
   step 1 runs the smoke test automatically; read its verdict rather than
   inferring one from the absence of red.
4. Move the tag:

   ```bash
   git tag -f workflows-v1 <merged-sha>
   git push -f origin workflows-v1
   ```

5. Verify a consumer executes the new behavior without receiving a commit.

Never promote the tag while this repository's own publishers are red.

### Verifying propagation honestly

Step 5 is the claim the whole migration rests on, and four green runs after a
promotion do not establish it. Green proves the publishers work; it does not
prove the promotion is why they changed. They could have been executing the new
definition already, for any number of reasons.

Take the negative control before promoting. Between step 1 and step 4 the
consumers still resolve the old definition, so dispatching a publisher in each
one then costs a single run apiece and produces the missing half of the
evidence:

- **before promotion** — the consumer runs show the *previous* release marker;
- **after promotion** — the same dispatch in the same repository shows the new
  one, with no commit in that repository between the two runs.

Absent-then-present is what makes the tag the cause. Record both sets of run
URLs together; the pre-promotion set is not a formality to be dropped once the
post-promotion set is green.

## Detecting an outdated stub

A stub is a file copied into the consumer, so the publishers duplicated one
thing that surviving #260 did not remove: the **interface**. When a central
definition gained an input the stub must pass, an older stub simply did not
pass it. The input arrived empty and nothing said so -- the same silent-failure
class as the four defects the migration itself hit.

Since dr-agents#268 every stub passes a `stub_version` literal equal to its own
`# <agent>-dr: vX.Y.Z` marker, and the first step of every definition compares
it against a `minimum_stub_version` literal embedded in that definition. Three
outcomes, each reported to **stdout and the step summary**, so a run is legible
to `gh run view --log` and not only in the UI:

| Outcome | Meaning | Fatal |
| --- | --- | --- |
| `stub-outdated` | The stub predates an input this publisher requires. Nothing was published. | yes |
| `stub-version-malformed` | The stub reported something this guard cannot compare. | yes |
| `stub-version-unknown` | The stub predates the guard and cannot report its version. | no |

Bump `minimum_stub_version` **only** when a definition gains an input a stub
must pass. All six must agree, and `bin/check` enforces that: a partial bump
would make the guard lie about what it requires, which is worse than not having
it.

### Why a literal and not the staged catalog version

The issue proposed comparing against the catalog version staged at
`catalog_ref`. Two measurements ruled that out.

Comparing against the *current* catalog version would fire on every routine
version bump, in consumers that are perfectly correct. A guard that alarms when
all is well is ignored within two releases, which reintroduces the silence by
another route. What the check actually needs to know is not "is this stub the
newest" but "is this stub too old for what this definition now requires", and
only a hand-bumped minimum expresses that.

And `reusable-publish-issue.yml` performs no checkout and takes no
`catalog_ref` -- a property `tests/test_reusable_ref_resolution.sh` asserts
rather than merely documents. A literal needs no staged catalog, so the issue
publisher needs no exception: the special case disappears instead of being
written down.

### What it cannot do

The mechanism is forward-only by construction. A stub old enough to predate the
guard cannot pass the input that would report it, which is why an empty
`stub_version` is reported but not fatal -- every stub installed before this
shipped is in that state, and failing them would break working consumers over a
usually benign condition. The check constrains future drift; it cannot
retroactively detect drift already present in an installed stub.

The operator-facing path remains: `bin/install` with no arguments reads each
stub's marker and reports it as `drifted` when it trails the catalog.

## Rollback

Repoint `workflows-v1` at the previous release commit and force-push the tag. No
consumer is touched, and no consumer needs to know a rollback happened.

## Tag protection

`workflows-v1` executes with the secrets of every consumer. It must be protected
so that only an authorized maintainer can move it. This is a requirement of
decision D4, which accepted a public catalog as the host on that condition.
