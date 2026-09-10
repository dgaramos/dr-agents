# Releasing the central publisher definition

The reusable publisher workflows in `.github/workflows/reusable-publish-*.yml`
and the composite action in `.github/actions/catalog-scripts/` are consumed by
other repositories. They are released under their own moving tag,
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

## The internal ref is self-referential

Each reusable workflow reaches the composite action by full
`dgaramos/dr-agents/.github/actions/catalog-scripts@workflows-v1`. A local `./`
path does not work: it resolves against the *caller's* workspace, which was
measured in `docs/spike-reusable-workflow-resolution.md`.

The internal ref therefore names the same tag being promoted. This is stable
rather than circular: the tag is moved to a commit whose workflows already
reference that tag name, so after promotion both the workflow and the action
resolve to the same commit.

## Bootstrapping the tag

The promotion procedure below moves an existing tag. The first release has to
create one, and it cannot be skipped: every reusable workflow reaches its
composite action at `@workflows-v1`, so until that ref resolves, no publisher
runs at all — not even this repository's own. `workflows-v1` was created as an
annotated tag at `1b5efd3`, the merge of #262, which is the first commit that
contains both the reusable workflows and the composite action.

## Publication scripts resolve inside the catalog

A reusable publisher runs no `actions/checkout`. The caller's workspace is empty,
so every path a publication step uses must be addressed inside the staged
catalog, through the `path` and `root` outputs of the composite action. This is
why `.github/scripts/` stays in this repository: it is the source the action
exposes, not a leftover of the vendored publishers.

The one script that reaches outside `.github/scripts/` is the metadata helper
under `core/`. `reusable-publish-pr-metadata.yml` takes a `metadata_helper`
input; when it is empty the catalog's own helper is used. A consumer's locally
installed helper can no longer be named by a caller-relative path, because
nothing checks the caller out.

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
