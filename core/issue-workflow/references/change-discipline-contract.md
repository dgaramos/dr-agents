# Change-discipline contract

## Purpose

This contract is the single portable source of truth for line-level change
discipline. It governs what a change is allowed to contain, not what the change
is for: the request decides the goal, and this contract decides how small and
how traceable the resulting diff is.

It applies wherever a workflow edits a target repository — implementing an
issue from an approved plan, or applying the minimal correction for an accepted
review finding — and it gives a reviewer the vocabulary to name a diff hunk
that does not answer the request.

It does not lower the evidence threshold for a finding and does not authorize
any publication.

## Simplicity rules

1. Write the minimum code that answers the request. A shorter solution that
   satisfies the stated behavior is preferred over a more general one that also
   satisfies it.
2. Introduce no abstraction for single-use code. A helper, wrapper, base class,
   interface, or indirection layer with exactly one caller is inlined at that
   caller instead.
3. Add no configurability or flexibility that the request did not ask for. No
   option, flag, parameter, hook, or extension point exists until something
   named in the request needs it.
4. Add no error handling for unreachable scenarios. Handle the failures the
   change can actually produce; a guard for a state the code cannot enter is
   dead weight that reads as a real case.

## Surgical rules

1. Do not modify adjacent code, comments, or formatting. A line that the
   request does not reach stays as it is, including its whitespace.
2. Follow the style already surrounding the edit, even where it differs from a
   style preferred elsewhere in the repository. Style is not the change.
3. Remove only the imports, variables, and functions that this change itself
   orphaned. An orphan is a symbol whose last reference this change deleted.
4. Do not remove pre-existing dead code. Something unused before the change was
   already unused; removing it belongs to a request of its own.
5. Every changed line must be traceable to the request — the issue, the
   approved plan, or the specific finding being fixed. A line that cannot be
   traced to one of those does not belong in the diff.

## Output note

A workflow that edits under this contract names what it deliberately left
alone, so that a noticed problem is neither silently fixed nor silently lost:

```md
**Observed, not changed:** <items | none>
```

Items are dead code, defects, or improvement opportunities noticed while making
the change and left outside its scope. Each item is named with its location and
left untouched. `none` is a valid and common value; it is not a placeholder to
be filled to look thorough. An item recorded here is a candidate for a separate
request, never a justification for widening the current diff.

## Reviewer counterpart

A review applies this contract through one finding category:

- **Category:** `Change discipline`.
- **Use for:** a diff hunk that does not trace to the request, an abstraction
  the request did not ask for, a cleanup of adjacent code, or a symbol left
  orphaned by the change.
- **Evidence:** the current `file:line` of the hunk, exactly as any other
  formal finding requires. A category is not an exemption from evidence.
- **Default class:** `nit`. An untraceable hunk is normally a non-blocking
  observation about the size of the diff.
- **`important`** only when the untraceable hunk alters behavior. The severity
  comes from the behavior change, not from the hunk being unrequested.

The existing rule stands unchanged: do not use style preference as a finding. A
hunk that merely reformats to a different but equally valid style is a style
preference, and it is out of this category as much as it is out of every other.

## Precedence

Where this contract conflicts with an approved plan or with an explicit
decision recorded for a finding, that plan or decision wins. The workflow
records the tension under `Observed, not changed:` and continues; it does not
reopen an approval gate to argue the contract, and it does not quietly narrow
what was approved.

Where this contract conflicts with a rule the target repository declares for
itself, the target's rule wins for that repository and the conflict is
surfaced rather than resolved silently.

## Attribution

The simplicity and surgical rules above are derived from §2 "Simplicity First"
and §3 "Surgical Changes" of `multica-ai/andrej-karpathy-skills`
(`skills/karpathy-guidelines/SKILL.md`), which its author declares MIT in
`.claude-plugin/plugin.json` and in its README. That repository ships no
LICENSE file and no copyright line, so the declaration is recorded here as
made rather than asserted as a grant.
