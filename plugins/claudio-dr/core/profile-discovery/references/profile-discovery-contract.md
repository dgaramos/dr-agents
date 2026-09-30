<!-- generated from core/profile-discovery/references/profile-discovery-contract.md by bin/sync-plugin-core-bundles.sh -- do not edit -->
# Project profile discovery contract

Before a project-aware workflow starts, resolve its target through
`core/target-resolution/references/target-resolution-contract.md`. When that
result supplies a checkout, inspect exactly this location:

```text
<repository-root>/.dr-agents/*/PROFILE.md
```

Use `core/profile-discovery/scripts/discover-project-profile.sh` when the
catalog checkout is available. It prints the sole matching profile path.

- One match: load that profile before applying project-specific behavior. The
  script prints its path on stdout and exits 0.
- No match and nothing profile-shaped anywhere else: a genuine absence. The
  script exits 0 silently. Continue with generic portable rules. Do not invent
  project-specific commands, metadata, or publishers. Issue execution still
  authorizes normal delivery actions; review and comment publication remain
  explicit.
- More than one match: stop and ask the caller to name the intended profile;
  never choose one by directory order. The script exits 3 with
  `ambiguous project profiles` on stderr.
- No match, but at least one rejected profile-shaped candidate: report it, as
  described below.

## Rejected candidates

A genuine absence and a profile the discovery search failed to accept must not
look the same, because a caller that reads an empty result as proof of absence
then reviews, plans, or ships without the project's own rules.

The accepting location above is exact and stays exact: a wider accepting search
would begin accepting files that are not profiles. So a near miss is reported
rather than accepted, and the accepting search is unchanged.

`discover-project-profile.sh` distinguishes the outcome by exit status and
stderr, never by stdout. stdout carries one meaning only — the path of an
accepted profile — so a rejected candidate is never printed there and cannot be
mistaken for a usable path.

- **Inside the profile directory.** A profile-shaped file under `.dr-agents/`
  that the accepting search does not match — directly in `.dr-agents/`, nested
  deeper than one project directory, or differing from `PROFILE.md` only in
  filename case — exits 4. stderr opens with
  `no project profile accepted; rejected project profile candidates:` and names
  every candidate with its rejection reason. The intent of a file in that
  directory is unambiguous, so this is a misplacement to correct.
- **Outside the profile directory.** A profile-shaped file at the repository
  root is reported on the same stderr lines but exits 0. Its intent is not
  established: that filename occurs in projects unrelated to this catalog, and
  failing on it would break discovery for repositories that are correct. It is
  distinguishable from an absence without being treated as one.

A consuming surface must not silently swallow either report. When discovery
returns a rejected candidate, the surface:

- treats no profile as loaded, exactly as for a genuine absence, and applies
  generic portable rules;
- reports the rejected candidate and its reason wherever it reports profile
  origin, instead of the plain no-profile wording, so a mistaken "no profile"
  briefing is visible at the point the briefing is built; and
- does not abort a supported no-profile flow on exit 4 alone. Exit 4 says a
  profile was probably intended, not that the run is invalid; where a profile is
  required, stop for the same reason a genuine absence would stop, naming the
  rejected path.

The current working directory is the repository root only for the special case
of an implicit target whose resolved checkout is that directory. When an
explicit target is in another repository, discovery runs against its resolved
checkout with `--root <checkout>` and the summary names the profile and its
checkout-relative origin. Without a checkout, do not inspect the current
directory: apply generic rules and declare `Profile: none (remote-only)`.
Never apply the current directory's profile to another target.

Profiles are target-project data. Do not copy them into plugins, core, or a
global agent. A wrapper may name an explicit profile for backwards
compatibility, but must not prevent this discovery procedure for new projects.

## Authorized spec source

A profile may declare one or more exact external spec trios using this section:

```md
## Spec source

- **Repository:** `owner/repository`
- **Authorized path:** `specs/<project>/<feature>/`
- **Authorized path:** `specs/<project>/<other-feature>/`
```

Each `Authorized path` bullet authorizes exactly one trio. Listing several does
not authorize any path between or above them, and it never authorizes a prefix:
a requested trio must match one declared bullet exactly.

`Repository` identifies the source when it is external; a profile may instead
declare a local repository identity when the trio lives in the target project.
It may also be one environment placeholder, such as
`${SPECS_REPOSITORY}`. The resolver substitutes it only from the invoking
environment; an unset, empty, or malformed value makes the source inaccessible
and the agent must stop. Placeholders do not support defaults, concatenation,
or shell evaluation.
Every `Authorized path` is a directory containing exactly `requirements.md`,
`design.md`, and `tasks.md`.

An agent may resolve an external spec only when all of these conditions hold:

- exactly one profile was discovered and it declares both fields;
- the requested trio path exactly matches one declared `Authorized path`;
- the source is accessible through an authorized integration or local checkout.

Missing, partial, ambiguous, or inaccessible declarations are not defaults. The
agent must not infer a repository, project, path, or alternate spec. A source
declaration authorizes resolution only; writing still requires explicit caller
authorization.
