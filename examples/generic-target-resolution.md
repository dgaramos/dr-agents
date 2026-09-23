# Generic target-resolution examples

These examples use placeholder repositories. Resolution is read-only and does
not authorize publication or mutation.

## Current checkout is the target

With no explicit reference, the current repository's `origin` identifies the
target and the current checkout supplies its profile:

```md
**Target:** example/project (checkout: /work/project)
**Profile:** project (/work/project/.dr-agents/project/PROFILE.md)
```

## Target checkout is under another configured root

Given an explicit PR for `example/service` and
`DR_AGENTS_REPO_ROOTS=/work:/projects`, an immediate child such as
`/projects/service-copy` is selected only when its normalized `origin` matches:

```md
**Target:** example/service (checkout: /projects/service-copy)
**Profile:** service (/projects/service-copy/.dr-agents/service/PROFILE.md)
```

The directory could have any name; a sibling named `service` with a different
remote is not a candidate.

## Target has no local checkout

When no matching remote is found, repository-qualified remote reads continue
without applying the current directory's profile:

```md
**Target:** example/remote-service (remote-only)
**Profile:** none (remote-only)
```

An adopting workflow uses commands scoped to `example/remote-service` and does
not run git in the unrelated current directory.

## Separately authorized remote branch write

With no checkout, an explicitly authorized write creates the branch through the
git-data API. The manifest names target paths and local sources; the message
file supplies the commit message byte for byte:

```json
[{"path": "docs/report.md", "file": "/work/out/report.md"}]
```

```text
remote-write.sh example/remote-service main report/2026-09 \
  /work/out/manifest.json /work/out/message.txt \
  --author 'Example Agent <agent@example.invalid>'
```

```json
{"commit": "<sha>", "ref": "refs/heads/report/2026-09", "files": 1}
```

A second write to the same branch adds `--update`. It descends from the branch's
current head, so the ref moves as a fast-forward and never needs `force`.

Resolution did not authorize this write; a separate explicit authorization did.
Existence is checked before any object is created, and an inconclusive check —
anything other than a definite 404 — stops the run rather than creating a
branch that may already exist. Authorship is passed in, so it is chosen rather
than inherited from whichever account the session authenticates; identity
belongs to the adopting workflow, not to this portable example.
