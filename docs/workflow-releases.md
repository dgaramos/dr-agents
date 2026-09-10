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

## Promotion procedure

1. Merge the change to `main`.
2. Dogfood it: this repository's own stubs point at `@main`, not at the tag, so
   every publisher here exercises the new definition before any consumer sees
   it.
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
