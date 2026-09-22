---
name: target-resolution
description: Resolve the repository targeted by an explicit reference, the specs source, or the current checkout before loading profiles or operating on repository state.
---

# Portable target resolution

Load `references/target-resolution-contract.md`, then run
`scripts/resolve-target.sh` with the caller's explicit repository reference, if
one exists. A spec-writing flow passes its already-resolved specs repository
with `--from-specs-repository`; the resolver never reads that environment
variable itself.

- In `checkout` mode, discover the target profile with
  `core/profile-discovery/scripts/discover-project-profile.sh --root <checkout>`
  and run local repository operations only in that checkout.
- In `remote-only` mode, do not load the current directory's profile or run git
  there on behalf of the target. Use repository-qualified remote reads and
  declare `**Profile:** none (remote-only)`.
- In `remote-only` mode, a separately authorized branch write uses
  `scripts/remote-write.sh`; with a checkout available, never invoke it.
- Always print the contract's `**Target:**` line before target-dependent output.

Resolution is read-only and grants no publication or mutation authority.
