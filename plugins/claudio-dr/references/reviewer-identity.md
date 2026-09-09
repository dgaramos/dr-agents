# Claudio DR identity

Load `core/pr-review/references/reviewer-identity-contract.md` before using a
publisher.

| Representation | Canonical value |
| --- | --- |
| Display name | Claudio DR |
| Publisher | Claudio DR GitHub App |
| Verified GitHub actor | `claudio-dr[bot]` |
| Co-authored-by trailer | `Co-Authored-By: claudio-dr[bot] <318764128+claudio-dr[bot]@users.noreply.github.com>` |

Repository guidance may override these workflow discovery paths:

| Operation | Workflow |
| --- | --- |
| review | `.github/workflows/publish-claudio-review.yml` |
| reply | `.github/workflows/publish-claudio-reply.yml` |
| resolve-thread | `.github/workflows/publish-claudio-resolve.yml` |
| create-issue | `.github/workflows/publish-claudio-issue.yml` |
| create-pr | `.github/workflows/publish-claudio-pr.yml` |
| apply-pr-metadata | `.github/workflows/publish-claudio-pr-metadata.yml` |

These paths are discovery candidates, not proof of availability. Follow
`core/pr-review/references/publication-routing-contract.md` to prefer the
App and require evidence before selecting personal fallback. A missing profile
does not imply an unavailable App; an unavailable operation does not make
the Claudio DR identity inactive.
