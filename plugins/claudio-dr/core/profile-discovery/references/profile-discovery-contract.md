# Project profile discovery contract

Before a project-aware workflow starts, establish the repository root from the
current working directory and inspect exactly this location:

```text
<repository-root>/.dr-agents/*/PROFILE.md
```

Use `core/profile-discovery/scripts/discover-project-profile.sh` when the
catalog checkout is available. It prints the sole matching profile path.

- One match: load that profile before applying project-specific behavior.
- No match: continue with generic portable rules. Do not invent project-specific
  commands, metadata, or publishers. Issue execution still authorizes normal
  delivery actions; review and comment publication remain explicit.
- More than one match: stop and ask the caller to name the intended profile;
  never choose one by directory order.

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
