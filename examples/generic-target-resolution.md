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
