# Portable findings-handling contract

## Verification before acting

Verify every finding against the current head before classifying or fixing it.
If the evidence location no longer exists or the described condition is gone,
classify the finding as `superseded` and do not act on it.

## Triage and decision gate

Classify each finding as exactly one of:

| Classification | Condition |
| --- | --- |
| `pertinent, in scope` | The finding is valid and its minimal fix belongs in this PR. |
| `pertinent, separate issue` | The finding is valid but its fix is out of scope for this PR. |
| `not pertinent` | The finding is invalid, already fixed, or the described condition does not exist on the current head. |
| `unverifiable` | Current-head evidence is insufficient to reach a reliable conclusion. |

Before any state-changing action, list **every** finding with current-head
evidence, classification, rationale, and a proposed action. Then ask the user
for a decision on each item individually. Never infer consent from a request to
handle findings generally.

For example, an itemized decision request can offer:

| Finding | Verdict | Ask the user to choose |
| --- | --- | --- |
| `#1` | pertinent, in scope | fix in this PR; reply only; leave open |
| `#2` | pertinent, separate issue | create a separate issue; reply only; leave open |
| `#3` | not pertinent | publish a factual reply; leave open; fix anyway |

Do not fix more than the finding describes. Do not refactor, clean up, or
extend beyond the minimal correction. If a fix would require touching files or
logic outside the PR's scope, offer a separate issue rather than deciding to
defer it unilaterally.

## Fixing

For each user-approved `pertinent, in scope` finding:

1. Make the minimal correction on the current head.
2. Run the profile's quality command. If it fails, stop; do not claim the
   finding is resolved until validation passes.
3. Create a dedicated commit for that finding. Include the PR/issue reference
   required by the target profile; never batch distinct findings without an
   explicit user decision.

If no profile is loaded, state that no quality command is available and ask
the user which validation to run before claiming resolution.

## Deferring out-of-scope findings

For each user-approved `pertinent, separate issue` finding, produce a
publication-ready issue draft using the
portable issue-authoring contract (`core/issue-authoring/references/issue-contract.md`).
The draft's context must reference the original finding and its evidence. Do
not create an unscoped code change as a substitute.

## Reply and resolution

Prepare reply text and thread-resolution text for every handled finding.
Do not publish a reply, resolve a thread, push, or merge unless the user
explicitly authorizes that external action.

For an approved fix: the reply states what changed, links the dedicated commit,
and records validation. For an approved separate issue: the reply links the
published issue. For a not-pertinent or unverifiable finding: publish a factual
reply only when the user selected that action; otherwise leave the thread open.

## Publisher-first thread actions

When authorized to publish, use the target profile's configured publisher
first, per the reply and resolution modes documented in
`core/pr-review/references/profile-contract.md`. Before dispatching, confirm
that the requested operation is available; after dispatching, verify the
expected reviewer App actor, target thread, and operation. Never mark a
finding resolved based only on a reply.

Use `core/pr-review/references/publication-routing-contract.md` for the App-first
route and personal fallback when the App operation is unavailable. This also
applies without a profile. Verify the authenticated actor and label any
personal fallback. Inspect partial or uncertain publication before retrying;
an author or target mismatch remains a failed publication.

## UI-significant diffs

<!-- bin/check anchor: "UI-significant" and "Design Brief" are load-bearing phrases guarded by bin/check. Do not reword without updating the corresponding grep assertions in bin/check. -->

When a PR diff is UI-significant — it touches component markup, layout,
interaction handlers, styling tokens, or screen-level templates — trigger design
discovery before classifying the affected findings. A diff is UI-significant
when at least one changed file matches a UI-related extension or path pattern
(`.html`, `.css`, `.scss`, `.vue`, `.jsx`, `.tsx`, component directories,
or an equivalent pattern named in the target profile).

1. Run `design-discovery` on the UI-significant portion of the diff, following
   the portable `core/design-discovery/SKILL.md` contract.
2. Include the resulting Design Brief as context in the classification and
   rationale for every finding that touches the UI-significant change.
3. Surface the Design Brief section in the finding's evidence block so that
   a reviewer can assess UX impact alongside code correctness.

When the diff is not UI-significant, skip this step and state `Design discovery:
not applicable` in the outcome summary.

## Outcome summary

Emit one summary block per handling session:

```md
## Findings handled — <reviewer name>

**PR/ref:** <ref>
**Head verified:** `<sha>`
**Pertinent, in scope:** N · **Separate issue:** N · **Not pertinent:** N · **Unverifiable:** N
**Validation:** <passed|failed|not run: reason>
**Decisions:** <per-finding user selections>
**Commits:** <finding → commit or none>
**Issues:** <finding → issue or none>
**Replies prepared:** N · **Published:** <N published|not requested|not published>
**Publication identity:** <reviewer App actor|personal fallback: @login|none>
```
