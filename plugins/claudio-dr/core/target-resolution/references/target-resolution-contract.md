# Target-resolution contract

## Precedence (RF-01)

Resolve the repository before profile discovery or any repository-dependent
operation. An explicit PR URL, issue URL, repository reference, or remote URL
wins. For an authorized spec-writing flow only, the caller's resolved specs
repository is next. The current checkout's `origin` is used only when neither
explicit source exists. If none can be resolved, stop with `Target: unknown`.

Resolving a target is read-only. It never authorizes a write, publication,
checkout creation, or credential lookup.

## Normalization (RF-02)

Normalize HTTPS, scp-style SSH, `ssh://`, `owner/repository`, and
`owner/repository#number` references to a host plus `owner/repository`. Strip a
terminal `.git`; compare host, owner, and repository without regard to case;
and preserve the normalized host in the result. Reject malformed input instead
of repairing or guessing it. A URL identifies its `reference.kind` as `pr` or
`issue`; a bare repository is `repo`; and `owner/repository#number` is
`number`, because resolving it as an issue or pull request would require a
network lookup that this resolver must not perform.

## Checkout location (RF-03)

Select the current checkout only when its normalized `origin` matches the
target. Otherwise inspect immediate child directories, including symlinks to
directories, of the roots in `DR_AGENTS_REPO_ROOTS`, matching exclusively by
normalized `origin`. When the variable is unset, use the parent of the current
repository, or the parent of the current directory outside a repository. A
directory name is never evidence. Skip missing roots with a warning. Multiple
matching checkouts are ambiguous and require a handoff listing every candidate.

## Modes (RF-06, RF-07)

`checkout` mode supplies an absolute local path. Run git and local reads in
that path (`git -C <checkout>` or an equivalent working directory), never in an
unrelated current directory. `remote-only` supplies no checkout; use
repository-qualified remote reads such as `gh --repo owner/repository` or
`gh api repos/owner/repository/...`, and never run git in the current directory
on the target's behalf.

## Profile discovery at the target (RF-05)

In `checkout` mode, discover the profile with
`discover-project-profile.sh --root <checkout>`. Report either the profile and
its path or `none (no profile at checkout)`. In `remote-only` mode, load no
profile and report `none (remote-only)`. Never apply the current directory's
profile to another target.

## Remote branch writes (RF-08, RNF-04)

In `remote-only` mode, a separately authorized write creates or updates a
branch in the target with
`core/target-resolution/scripts/remote-write.sh OWNER/REPO BASE_BRANCH
NEW_BRANCH MANIFEST_PATH MESSAGE_FILE [--update]`, where the manifest is
`[{"path":"<path in the target>","file":"<absolute local path>"}]`.

The script uses the authenticated `gh` session and never reads, stores, or
accepts a token. It reads the new ref first and refuses an existing branch
unless `--update` is passed, so no blob, tree, or commit is created before that
check. It then reads the base ref and its commit, uploads one base64 blob per
manifest entry, creates one tree on the base tree, creates one commit whose
`message` is the message file byte for byte, and creates the ref — or, with
`--update`, moves it with `force: false`. File bytes and the message are passed
through `jq`-built JSON to `gh api --input`; they are never interpolated into a
shell word.

It prints `{"commit":"<sha>","ref":"refs/heads/<branch>","files":<count>}` and,
on failure, reports already-created SHAs on stderr. It never opens a pull
request, and the commit is authored by the authenticated personal account, so
any adapter co-authorship must appear in the message file. When a checkout is
available, use it; this script is for `remote-only` mode.

## Publisher selection at the target (RF-07)

When a separately authorized workflow publishes, select the publisher against
the resolved `owner/repository`, not the current directory's repository. Apply
`core/pr-review/references/publication-routing-contract.md` independently to
each publication operation. Target resolution does not alter its authorization,
App precedence, fallback evidence, or verification requirements.

## Summary line (RF-11)

Every adopting summary begins with these target and profile facts:

```md
**Target:** owner/repository (checkout: /absolute/path)
**Profile:** project (/absolute/path/.dr-agents/project/PROFILE.md)
```

or:

```md
**Target:** owner/repository (remote-only)
**Profile:** none (remote-only)
```

When a checkout has no profile, use `**Profile:** none (no profile at
checkout)`. Failure before resolution uses `**Target:** unknown`.

## Failure handling (RF-01, RF-02, RF-03)

Malformed references stop without output from the resolver. An unknown target
stops with a handoff. Ambiguous checkouts stop and list the candidates; never
select one by directory order. Missing search roots are warnings, not failures.
No failure mode authorizes cloning, network discovery, mutation, or fallback to
the current directory's repository.
