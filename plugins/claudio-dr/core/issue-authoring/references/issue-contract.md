# Portable issue authoring contract

## Mode detection

Before drafting, classify the input into one of four modes. The agent may
override classification with an explicit prefix (e.g. `bug: …`, `feature: …`);
otherwise auto-detect from the input content:

| Mode | Detection signal |
|---|---|
| `bug` | stacktrace, error message, "broken", "doesn't work", wrong behavior |
| `feature` | new capability, user need, "it would be nice if", "add support for" |
| `chore` | tech debt, refactor, dependency update, cleanup, "remove", "migrate" |
| `spike` | open-ended uncertainty, research question, "how should we", "explore" |

### Bug mode

Before drafting, investigate the codebase:

1. Read every file referenced in the stacktrace or error message.
2. Grep for the error site and any relevant call sites.
3. Check `git log` for recent changes in the affected area.
4. Document: likely cause, reproduction steps, and impact.

Include these findings in the draft as an annotated stack and a root cause
hypothesis. Do not ask questions — investigate first.

### Feature mode

Run a short discovery pass before drafting:

- When the input is vague (no clear problem, no affected users, no alternatives
  mentioned): ask at most 3 focused questions covering problem, affected users,
  and alternatives considered. Wait for answers before drafting.
- When the input is already detailed (problem is clear, scope is defined): skip
  questions and draft immediately.

When the input includes a Design Brief from `design-discovery`, use its handoff
as the discovery result. Incorporate the evidence, UX direction, constraints,
accessibility considerations, success criteria, assumptions, and open questions
into the existing issue structure where relevant. Do not add a new mandatory
issue section, publish the design artifact, or treat the brief as authorization
to create the issue.

When the profile declares an authorized exact spec source and its trio is
available there, read `requirements.md` for acceptance criteria and `design.md`
for constraints. Treat it as context only, include `Spec: <location>` in the
body without a new mandatory section, and preserve every relevant declared
criterion ID and its criterion context in the acceptance-criteria checklist.
With no complete, exact, accessible declaration, do not infer or access an
external repository or path. If the authorized trio lacks criterion IDs or
task-to-criterion references, state that traceability limitation in the draft
without inventing references.

When a profile explicitly requires accepted specs for authoring, inspect the
resolved optional `spec.yaml`. Stop with a handoff when it is missing or its
status is not `accepted`; do not infer that a draft, review, or superseded spec
is current.

### Chore and spike modes

Before drafting, assess scope and risk:

- For `chore`: identify affected files, estimate change surface, and flag any
  breaking-change risk.
- For `spike`: define the question to answer and the done criterion explicitly
  in the draft.

No questions are required; draft after the assessment.

## Draft-first behavior

Always produce a complete draft before asking anything except for the feature
mode vague-input case above. Ask only for decisions that are materially missing
and cannot be inferred from the problem statement or the loaded profile. Do not
ask for labels, assignees, milestones, or Projects — those are profile-owned.
Do not publish until the user explicitly authorizes it.

## Issue structure

Every issue draft must include:

- **Context**: the concrete problem or gap being addressed; one or two sentences.
- **What to do**: the minimal set of actions needed to close the issue; use a
  short bulleted list.
- **Expected result**: what the system looks like after the issue is resolved.
- **Acceptance criteria**: a checklist of verifiable conditions; each item is
  falsifiable on its own. Phrase as: "Given …, when …, then …".
- **Dependencies** *(omit if none)*: explicit `blocked-by` or `blocking` links.
- **Limitations** *(omit if none)*: known constraints or out-of-scope items.

Omit sections that add no information for this specific issue. Do not add
sections that are not in this list.

## Profile-owned fields

The following fields belong to the target profile and must not be hardcoded in
the draft:

- labels
- assignees
- milestone
- Projects
- issue templates

When a profile supplies these values, apply them exactly. When no profile is
loaded, use known repository guidance and state which metadata is unknown.
Do not invent missing profile-owned fields or block an otherwise authorized
publication solely because no profile exists.

## Publication boundary

Publish only when the user explicitly authorizes issue publication. Follow
`core/pr-review/references/publication-routing-contract.md`: use the executing
adapter's `create-issue` App publisher whenever available. An absent profile
does not itself justify personal fallback; discover the documented publisher.

If evidence proves the App operation unavailable, the existing authenticated
`gh` account may publish the authorized issue unless App-only publication is
required. Announce the reason and verify the actual personal author. Without
authorization or a usable route, return the complete draft as `not published`.

## Publication mechanics

1. Resolve the route through the publication routing contract. Dispatch an
   available App workflow with title, body, and declared metadata inputs.
   Never choose `gh issue create` or a personal API call merely for convenience.
2. For a proven-unavailable App publisher, use structured REST requests through
   the authenticated personal `gh` account. Do not query Projects while
   creating an ordinary issue; handle Project membership separately.
3. Retain the applicable repository issue template's headings and structure.
   Without a profile, read repository guidance and use only known metadata;
   do not invent labels, milestones, or Project requirements.
4. Retrieve the created issue and verify author, repository, title, and body
   against the selected route. A mismatched author or target is a failed
   publication; inspect any existing result before retrying. A failure whose
   publication outcome is unknown must never trigger blind personal fallback.

## Draft summary

Emit one summary block per authoring session:

```md
## Issue draft — <author name>

**Title:** <issue title>
**Profile:** <profile name or none>
**Profile-owned fields:** <applied: labels, milestone, … | unknown: profile not loaded>
**Publication:** <not requested|not published|published by <author name> as issue #N>
```
