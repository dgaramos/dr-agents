# Cody DR identity

Load `core/pr-review/references/reviewer-identity-contract.md` before using a
publisher.

| Representation | Canonical value |
| --- | --- |
| Display name | Cody DR |
| Publisher | Cody DR GitHub App |
| Verified GitHub actor | `cody-dr[bot]` |
| Co-authored-by trailer | `Co-Authored-By: cody-dr[bot] <318732897+cody-dr[bot]@users.noreply.github.com>` |

Repository guidance may override these workflow discovery paths:

| Operation | Workflow |
| --- | --- |
| review | `.github/workflows/publish-cody-review.yml` |
| reply | `.github/workflows/publish-cody-reply.yml` |
| resolve-thread | `.github/workflows/publish-cody-resolve.yml` |
| create-issue | `.github/workflows/publish-cody-issue.yml` |
| create-pr | `.github/workflows/publish-cody-pr.yml` |
| apply-pr-metadata | `.github/workflows/publish-cody-pr-metadata.yml` |

These paths are discovery candidates, not proof of availability. Follow
`core/pr-review/references/publication-routing-contract.md` to prefer the
App and require evidence before selecting personal fallback. A missing profile
does not imply an unavailable App; an unavailable operation does not make
the Cody DR identity inactive.
