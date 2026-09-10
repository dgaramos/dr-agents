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

## Promotion procedure

1. Merge the change to `main`.
2. Dogfood it: this repository's own stubs point at `@main`, not at the tag, so
   every publisher here exercises the new definition before any consumer sees
   it. `bin/check` enforces both halves of that split — the twelve stubs under
   `.github/workflows/` must pin `@main` and the twelve templates under
   `plugins/*/workflows/` must pin `@workflows-v1` — so the two refs cannot be
   swapped by accident.
3. Confirm the publishers of this repository ran green.
4. Move the tag:

   ```bash
   git tag -f workflows-v1 <merged-sha>
   git push -f origin workflows-v1
   ```

5. Verify a consumer executes the new behavior without receiving a commit.

Never promote the tag while this repository's own publishers are red.

## Rollback

Repoint `workflows-v1` at the previous release commit and force-push the tag. No
consumer is touched, and no consumer needs to know a rollback happened.

## Tag protection

`workflows-v1` executes with the secrets of every consumer. It must be protected
so that only an authorized maintainer can move it. This is a requirement of
decision D4, which accepted a public catalog as the host on that condition.
