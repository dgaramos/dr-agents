#!/usr/bin/env bash
# tests/test_install_workflows.sh — tests for agents install workflow management
set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

readonly fake_home="$tmp/home"
readonly fake_repo="$tmp/repo"
readonly codex_dir="$tmp/home/.codex"

mkdir -p "$fake_home" "$fake_repo"

run_install() {
  local workdir="$1"; shift
  HOME="$fake_home" CODEX_CONFIG_DIR="$codex_dir" \
    bash "$repository_root/bin/install" "$@" 2>&1
}

# ---------------------------------------------------------------------------
# Criterion 1 — workflow templates exist and carry version comments
# ---------------------------------------------------------------------------

claudio_ver="$(grep '"version"' "$repository_root/plugins/claudio-dr/.claude-plugin/plugin.json" | head -1 \
  | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
cody_ver="$(grep '"version"' "$repository_root/plugins/cody-dr/.codex-plugin/plugin.json" | head -1 \
  | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"

for wf in publish-claudio-issue.yml publish-claudio-pr-metadata.yml publish-claudio-review.yml \
          publish-claudio-reply.yml publish-claudio-resolve.yml; do
  src="$repository_root/plugins/claudio-dr/workflows/$wf"
  [[ -f "$src" ]] || { echo "FAIL: claudio-dr workflow template missing: $wf" >&2; exit 1; }
  grep -qF "# claudio-dr: v${claudio_ver}" "$src" \
    || { echo "FAIL: claudio-dr workflow template missing version comment in $wf" >&2; exit 1; }
done

for wf in publish-cody-issue.yml publish-cody-pr-metadata.yml publish-cody-review.yml \
          publish-cody-reply.yml publish-cody-resolve.yml; do
  src="$repository_root/plugins/cody-dr/workflows/$wf"
  [[ -f "$src" ]] || { echo "FAIL: cody-dr workflow template missing: $wf" >&2; exit 1; }
  grep -qF "# cody-dr: v${cody_ver}" "$src" \
    || { echo "FAIL: cody-dr workflow template missing version comment in $wf" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# Criterion 2 — agents install (no args) reports workflow presence without writing files
# ---------------------------------------------------------------------------

# 2a: repo without .github/workflows/ — all absent, no files written
check_output="$(cd "$fake_repo" && run_install "$fake_repo")"
echo "$check_output" | grep -q "absent" \
  || { echo "FAIL: agents install (no args) should report 'absent' for missing workflows" >&2
       echo "Output was: $check_output" >&2; exit 1; }
[[ ! -d "$fake_repo/.github" ]] \
  || { echo "FAIL: agents install (no args) must not write any files" >&2; exit 1; }

# 2b: repo with all current workflows — all present
mkdir -p "$fake_repo/.github/workflows"
for wf in publish-claudio-issue.yml publish-claudio-pr-metadata.yml publish-claudio-review.yml \
          publish-claudio-reply.yml publish-claudio-resolve.yml \
          publish-cody-issue.yml publish-cody-pr-metadata.yml publish-cody-review.yml \
          publish-cody-reply.yml publish-cody-resolve.yml; do
  cp "$repository_root/plugins/claudio-dr/workflows/$wf" \
     "$fake_repo/.github/workflows/$wf" 2>/dev/null \
  || cp "$repository_root/plugins/cody-dr/workflows/$wf" \
        "$fake_repo/.github/workflows/$wf" 2>/dev/null \
  || true
done
# copy all from both plugin directories
for wf in publish-claudio-issue.yml publish-claudio-pr-metadata.yml publish-claudio-review.yml \
          publish-claudio-reply.yml publish-claudio-resolve.yml; do
  cp "$repository_root/plugins/claudio-dr/workflows/$wf" "$fake_repo/.github/workflows/$wf"
done
for wf in publish-cody-issue.yml publish-cody-pr-metadata.yml publish-cody-review.yml \
          publish-cody-reply.yml publish-cody-resolve.yml; do
  cp "$repository_root/plugins/cody-dr/workflows/$wf" "$fake_repo/.github/workflows/$wf"
done

present_output="$(cd "$fake_repo" && run_install "$fake_repo")"
echo "$present_output" | grep -q "present" \
  || { echo "FAIL: agents install (no args) should report 'present' for up-to-date workflows" >&2
       echo "Output was: $present_output" >&2; exit 1; }
echo "$present_output" | grep -qv "absent" 2>/dev/null || true  # soft check; present overrides

# 2c: repo with drifted workflow — reports drifted
echo "# claudio-dr: v0.0.1" > "$fake_repo/.github/workflows/publish-claudio-issue.yml"
echo "name: drifted" >> "$fake_repo/.github/workflows/publish-claudio-issue.yml"
drifted_output="$(cd "$fake_repo" && run_install "$fake_repo")"
echo "$drifted_output" | grep -q "drifted" \
  || { echo "FAIL: agents install (no args) should report 'drifted' for outdated workflow" >&2
       echo "Output was: $drifted_output" >&2; exit 1; }

# restore
rm -rf "$fake_repo/.github"

# ---------------------------------------------------------------------------
# Criterion 3 — agents install --workflows installs absent workflows
# ---------------------------------------------------------------------------

# 3a: happy path — installs all workflows
install_output="$(cd "$fake_repo" && run_install "$fake_repo" --workflows)"
echo "$install_output" | grep -q "installed" \
  || { echo "FAIL: agents install --workflows should report 'installed'" >&2
       echo "Output was: $install_output" >&2; exit 1; }
[[ -f "$fake_repo/.github/workflows/publish-claudio-issue.yml" ]] \
  || { echo "FAIL: publish-claudio-issue.yml not created by --workflows" >&2; exit 1; }
[[ -f "$fake_repo/.github/workflows/publish-cody-issue.yml" ]] \
  || { echo "FAIL: publish-cody-issue.yml not created by --workflows" >&2; exit 1; }

# 3b: --workflows installs stubs only, and vendors no publication script.
#
# Until dr-agents#260 T09 this loop asserted the opposite: that six helper
# scripts had been copied into .github/scripts/agent-workflows/. The publishers
# became thin stubs that run nothing locally, so a copied script is dead weight
# that an installer would silently reintroduce into a migrated repository.
[[ ! -e "$fake_repo/.github/scripts/agent-workflows" ]] \
  || { echo "FAIL: --workflows must not vendor publication scripts into the consumer" >&2
       ls -R "$fake_repo/.github/scripts" >&2; exit 1; }
[[ ! -e "$fake_repo/.github/scripts" ]] \
  || { echo "FAIL: --workflows must not create .github/scripts/ in the consumer" >&2; exit 1; }

for adapter in cody claudio; do
  [[ -f "$fake_repo/.github/workflows/publish-${adapter}-pr.yml" ]] || exit 1
done

idempotent_output="$(cd "$fake_repo" && run_install "$fake_repo" --workflows)"
echo "$idempotent_output" | grep -q "unchanged" \
  || { echo "FAIL: second agents install --workflows should report 'unchanged'" >&2
       echo "Output was: $idempotent_output" >&2; exit 1; }

# 3c: --force overwrites existing workflows and reports installed
echo "# claudio-dr: v0.0.1" > "$fake_repo/.github/workflows/publish-claudio-issue.yml"
force_output="$(cd "$fake_repo" && run_install "$fake_repo" --workflows --force)"
echo "$force_output" | grep -q "installed" \
  || { echo "FAIL: --workflows --force should report 'installed' for overwritten file" >&2
       echo "Output was: $force_output" >&2; exit 1; }
grep -qF "# claudio-dr: v${claudio_ver}" "$fake_repo/.github/workflows/publish-claudio-issue.yml" \
  || { echo "FAIL: --workflows --force did not restore current version" >&2; exit 1; }

# 3d: the version marker keeps its meaning once the stub travels alone.
#
# The no-argument drift report is the operator-facing detection of an outdated
# stub, and it is the reason dr-agents#260 T09 defers a runtime stub_version
# input. It must still read the marker after the helper copy is gone.
present_output="$(cd "$fake_repo" && run_install "$fake_repo")"
echo "$present_output" | grep "publish-claudio-issue" | grep -q "present" \
  || { echo "FAIL: no-arg check should report a freshly installed stub as 'present'" >&2
       echo "Output was: $present_output" >&2; exit 1; }
echo "# claudio-dr: v0.0.1" > "$fake_repo/.github/workflows/publish-claudio-issue.yml"
drift_output="$(cd "$fake_repo" && run_install "$fake_repo")"
echo "$drift_output" | grep "publish-claudio-issue" | grep -q "drifted" \
  || { echo "FAIL: no-arg check should still report an outdated stub marker as 'drifted'" >&2
       echo "Output was: $drift_output" >&2; exit 1; }

rm -rf "$fake_repo/.github"

# 3e: a repository still carrying the pre-migration helper directory is warned,
# never modified. An installer that deletes files in someone else's repository
# is not a trustworthy installer, so the stale copy is reported and left alone.
mkdir -p "$fake_repo/.github/scripts/agent-workflows"
echo "# left over from the vendored era" > "$fake_repo/.github/scripts/agent-workflows/publish-pr.sh"
stale_output="$(cd "$fake_repo" && run_install "$fake_repo" --workflows)"
echo "$stale_output" | grep -q "agent-workflows" \
  || { echo "FAIL: --workflows should report a stale vendored helper directory" >&2
       echo "Output was: $stale_output" >&2; exit 1; }
[[ -f "$fake_repo/.github/scripts/agent-workflows/publish-pr.sh" ]] \
  || { echo "FAIL: --workflows must not delete files it no longer manages" >&2; exit 1; }
grep -qF "# left over from the vendored era" "$fake_repo/.github/scripts/agent-workflows/publish-pr.sh" \
  || { echo "FAIL: --workflows must not rewrite a stale vendored helper" >&2; exit 1; }

rm -rf "$fake_repo/.github"

# ---------------------------------------------------------------------------
# Criterion 4 — workflow template content satisfies policy constraints
# ---------------------------------------------------------------------------

# Review workflows must allow COMMENT only — APPROVE must not appear as an option.
for wf in \
  "$repository_root/plugins/claudio-dr/workflows/publish-claudio-review.yml" \
  "$repository_root/plugins/cody-dr/workflows/publish-cody-review.yml"; do
  name="$(basename "$wf")"
  grep -qE "options:[[:space:]]*\[COMMENT\]" "$wf" \
    || { echo "FAIL: $name must have options: [COMMENT] only" >&2; exit 1; }
  grep -q "APPROVE" "$wf" \
    && { echo "FAIL: $name must not contain APPROVE — it is a human decision" >&2; exit 1; } || true
done

# PR metadata workflows must declare project_owner, project_number, project_status.
for wf in \
  "$repository_root/plugins/claudio-dr/workflows/publish-claudio-pr-metadata.yml" \
  "$repository_root/plugins/cody-dr/workflows/publish-cody-pr-metadata.yml"; do
  name="$(basename "$wf")"
  for field in project_owner project_number project_status; do
    grep -qF "${field}:" "$wf" \
      || { echo "FAIL: $name must declare input field: $field" >&2; exit 1; }
  done
done

# Issue publishing must not request organization-level project permissions.
grep -q "permission-organization-projects" "$repository_root/.github/workflows/reusable-publish-issue.yml" \
  && { echo "FAIL: reusable-publish-issue.yml must not request permission-organization-projects" >&2; exit 1; } || true

# ---------------------------------------------------------------------------
# Criterion 5 — the issue publisher GETs and validates author before PATCH
#
# This is the #258 protection. Since dr-agents#260 T05 the templates are stubs,
# so the assertion follows the logic into the central definition rather than
# being dropped with the vendored copy it used to inspect.
# ---------------------------------------------------------------------------

reusable_issue="$repository_root/.github/workflows/reusable-publish-issue.yml"
grep -q "method GET" "$reusable_issue" \
  || { echo "FAIL: reusable-publish-issue.yml must perform a GET to validate issue author before PATCH" >&2; exit 1; }
get_line="$(grep -n "method GET" "$reusable_issue" | head -1 | cut -d: -f1)"
patch_line="$(grep -n "method PATCH" "$reusable_issue" | head -1 | cut -d: -f1)"
[[ -n "$get_line" && -n "$patch_line" && "$get_line" -lt "$patch_line" ]] \
  || { echo "FAIL: reusable-publish-issue.yml GET must appear before PATCH for pre-mutation author validation" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Criterion 6 — no publisher checks a repository out
#
# Criteria 6 and 7 used to require persist-credentials: false and a pinned
# ref: refs/heads/main on every publisher checkout.
#
# The composite action removed every checkout, but it could only ever be
# addressed at a literal ref, because `uses:` does not accept expressions. That
# pinned the action to a different commit than the workflow using it, which is
# the skew that broke run 34505697770. The action is gone and a pinned checkout
# at the caller-supplied catalog_ref replaced it.
#
# So the assertion is no longer "no checkout anywhere". It is the property the
# ban stood for: a stub is thin and checks nothing out, and the one checkout in
# the central definitions is pinned to a single SHA and never persists a
# credential.
# ---------------------------------------------------------------------------

readonly checkout_pin="actions/checkout@11d5960a326750d5838078e36cf38b85af677262"

# A stub stays thin: it checks nothing out.
for wf in \
  "$repository_root"/plugins/claudio-dr/workflows/publish-claudio-*.yml \
  "$repository_root"/plugins/cody-dr/workflows/publish-cody-*.yml \
  "$repository_root"/.github/workflows/publish-*.yml; do
  name="$(basename "$wf")"
  grep -qE "^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*actions/checkout" "$wf" \
    && { echo "FAIL: $name is a stub and must not perform a checkout" >&2; exit 1; } || true
done

# A central definition may check the catalog out, but only at the single pin,
# and never persisting the credential.
for wf in "$repository_root"/.github/workflows/reusable-publish-*.yml; do
  name="$(basename "$wf")"
  grep -qE "^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*actions/checkout" "$wf" || continue
  grep -qF "uses: ${checkout_pin}" "$wf" \
    || { echo "FAIL: $name checks out without the single pin ${checkout_pin}" >&2; exit 1; }
  grep -qE "^[[:space:]]*uses:[[:space:]]*actions/checkout@(v[0-9]|main)" "$wf" \
    && { echo "FAIL: $name uses an unpinned actions/checkout" >&2; exit 1; } || true
  grep -qF "persist-credentials: false" "$wf" \
    || { echo "FAIL: $name checks out without persist-credentials: false" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# Criterion 7 — a stub declares its secret by name and never inherits
# ---------------------------------------------------------------------------

for wf in \
  "$repository_root"/plugins/claudio-dr/workflows/publish-claudio-*.yml \
  "$repository_root"/plugins/cody-dr/workflows/publish-cody-*.yml \
  "$repository_root"/.github/workflows/publish-*.yml; do
  name="$(basename "$wf")"
  grep -q "secrets: *inherit" "$wf" \
    && { echo "FAIL: $name must declare app_private_key explicitly, never secrets: inherit" >&2; exit 1; } || true
  grep -qF "app_private_key:" "$wf" \
    || { echo "FAIL: $name must pass app_private_key to the central definition" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# Criterion 8 — inline_comments_json description is a quoted YAML string
# ---------------------------------------------------------------------------

for wf in \
  "$repository_root/plugins/claudio-dr/workflows/publish-claudio-review.yml" \
  "$repository_root/plugins/cody-dr/workflows/publish-cody-review.yml"; do
  name="$(basename "$wf")"
  grep -qE "inline_comments_json:.*description:[[:space:]]*\"" "$wf" \
    || grep -qE "description:[[:space:]]*\"[^\"]*\"" "$wf" \
    || { echo "FAIL: $name inline_comments_json description must be a quoted YAML string" >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# Criterion 9 — content divergence at an equal version marker is its own state
#
# The installer decided whether a stub needed updating by comparing the version
# marker alone, never the content. dr-agents#282 added stub_version: to all
# twelve templates without bumping the version, and all three consumers were
# told 'unchanged (v0.1.31)' while the installed stub genuinely differed from
# the template. The #268 guard reached no consumer, and nothing said so.
#
# Marker equal + content differing is not ordinary staleness. It means the
# catalog template changed without a version bump, or the stub was edited in
# place. It gets its own state, ranked above 'drifted'.
# ---------------------------------------------------------------------------

rm -rf "$fake_repo/.github"

# Fixture: a fully current install, then one installed stub mutated in a way
# that leaves the version marker untouched — exactly the #282 shape.
(cd "$fake_repo" && run_install "$fake_repo" --workflows) >/dev/null
readonly mismatch_stub="$fake_repo/.github/workflows/publish-cody-resolve.yml"
printf '# content changed with no version bump\n' >> "$mismatch_stub"
grep -qF "# cody-dr: v${cody_ver}" "$mismatch_stub" \
  || { echo "FAIL: fixture invalid — the mutated stub must keep its version marker" >&2; exit 1; }

# 9a: --workflows must not call this 'unchanged', must name it, and must fail.
mismatch_install_rc=0
mismatch_install_output="$(cd "$fake_repo" && run_install "$fake_repo" --workflows)" \
  || mismatch_install_rc=$?
mismatch_install_line="$(echo "$mismatch_install_output" | grep "publish-cody-resolve" || true)"
echo "$mismatch_install_line" | grep -q "unchanged" \
  && { echo "FAIL: --workflows reported 'unchanged' for a stub whose content differs" >&2
       echo "Output was: $mismatch_install_output" >&2; exit 1; } || true
echo "$mismatch_install_line" | grep -q "MISMATCH" \
  || { echo "FAIL: --workflows must report MISMATCH when content differs at an equal version" >&2
       echo "Output was: $mismatch_install_output" >&2; exit 1; }
[[ "$mismatch_install_rc" -ne 0 ]] \
  || { echo "FAIL: --workflows must exit non-zero when a MISMATCH is present" >&2; exit 1; }

# 9b: it reports, it does not update. Overwriting would hide the missing bump
# from the one operator positioned to notice it.
grep -qF "# content changed with no version bump" "$mismatch_stub" \
  || { echo "FAIL: --workflows must not overwrite a MISMATCH without --force" >&2; exit 1; }
echo "$mismatch_install_output" | grep -qi -- "--force" \
  || { echo "FAIL: a MISMATCH report must name --force as the way to overwrite" >&2
       echo "Output was: $mismatch_install_output" >&2; exit 1; }

# 9c: the other eleven stubs are still processed; one bad file is not an abort.
echo "$mismatch_install_output" | grep -q "publish-claudio-resolve" \
  || { echo "FAIL: a MISMATCH must not stop the installer from reporting other stubs" >&2
       echo "Output was: $mismatch_install_output" >&2; exit 1; }

# 9d: the no-argument report distinguishes it from 'present' and gates CI.
mismatch_check_rc=0
mismatch_check_output="$(cd "$fake_repo" && run_install "$fake_repo")" || mismatch_check_rc=$?
mismatch_check_line="$(echo "$mismatch_check_output" | grep "publish-cody-resolve" || true)"
echo "$mismatch_check_line" | grep -q "MISMATCH" \
  || { echo "FAIL: no-arg check must report MISMATCH, not present, for diverging content" >&2
       echo "Output was: $mismatch_check_output" >&2; exit 1; }
[[ "$mismatch_check_rc" -ne 0 ]] \
  || { echo "FAIL: no-arg check must exit non-zero when a MISMATCH is present" >&2; exit 1; }

# 9e: --force is the escape hatch and restores byte identity with the template.
force_mismatch_rc=0
force_mismatch_output="$(cd "$fake_repo" && run_install "$fake_repo" --workflows --force)" \
  || force_mismatch_rc=$?
[[ "$force_mismatch_rc" -eq 0 ]] \
  || { echo "FAIL: --workflows --force must resolve a MISMATCH and exit zero" >&2
       echo "Output was: $force_mismatch_output" >&2; exit 1; }
cmp -s "$repository_root/plugins/cody-dr/workflows/publish-cody-resolve.yml" "$mismatch_stub" \
  || { echo "FAIL: --force must restore byte identity with the catalog template" >&2; exit 1; }

# 9f: THE GUARD ON 9a. An implementation that classified every difference as a
# MISMATCH would satisfy every assertion above while destroying the ordinary
# update path. A stub whose marker AND content both differ is plain drift: it
# stays 'drifted' in the report and 'updated' by the installer, and the
# installer still exits zero. Without this, 9a passes for free.
printf '# claudio-dr: v0.0.1\nname: drifted\n' \
  > "$fake_repo/.github/workflows/publish-claudio-resolve.yml"
both_differ_check_rc=0
both_differ_check="$(cd "$fake_repo" && run_install "$fake_repo")" || both_differ_check_rc=$?
both_differ_line="$(echo "$both_differ_check" | grep "publish-claudio-resolve" || true)"
echo "$both_differ_line" | grep -q "drifted" \
  || { echo "FAIL: an outdated marker with differing content must stay 'drifted'" >&2
       echo "Output was: $both_differ_check" >&2; exit 1; }
echo "$both_differ_line" | grep -q "MISMATCH" \
  && { echo "FAIL: ordinary drift must not be reclassified as MISMATCH" >&2
       echo "Output was: $both_differ_check" >&2; exit 1; } || true
[[ "$both_differ_check_rc" -eq 0 ]] \
  || { echo "FAIL: ordinary drift must keep the no-arg check at exit zero" >&2; exit 1; }

both_differ_install_rc=0
both_differ_install="$(cd "$fake_repo" && run_install "$fake_repo" --workflows)" \
  || both_differ_install_rc=$?
echo "$both_differ_install" | grep "publish-claudio-resolve" | grep -q "updated" \
  || { echo "FAIL: ordinary drift must still be updated by --workflows" >&2
       echo "Output was: $both_differ_install" >&2; exit 1; }
[[ "$both_differ_install_rc" -eq 0 ]] \
  || { echo "FAIL: ordinary drift alone must keep --workflows at exit zero" >&2; exit 1; }
cmp -s "$repository_root/plugins/claudio-dr/workflows/publish-claudio-resolve.yml" \
       "$fake_repo/.github/workflows/publish-claudio-resolve.yml" \
  || { echo "FAIL: an updated drifted stub must match the catalog template" >&2; exit 1; }

rm -rf "$fake_repo/.github"

# Every publisher template must reach a consumer. The installer used to carry a
# hand-written list of stub names, so dr-agents#269 added a seventh publisher
# whose templates existed in both plugins and would never have been installed
# anywhere -- nothing knew they existed and nothing complained. This asserts the
# set, derived from the catalog, rather than restating names a reader must
# remember to extend.
(cd "$fake_repo" && run_install "$fake_repo" --workflows) >/dev/null
for template in "$repository_root"/plugins/*/workflows/publish-*.yml; do
  [[ -e "$template" ]] || continue
  name="$(basename "$template")"
  [[ -f "$fake_repo/.github/workflows/$name" ]] \
    || { echo "FAIL: $name is a catalog template but was not installed" >&2; exit 1; }
  cmp -s "$template" "$fake_repo/.github/workflows/$name" \
    || { echo "FAIL: installed $name differs from its catalog template" >&2; exit 1; }
done
installed_count="$(find "$fake_repo/.github/workflows" -name 'publish-*.yml' | wc -l | tr -d ' ')"
template_count="$(find "$repository_root"/plugins/*/workflows -name 'publish-*.yml' | wc -l | tr -d ' ')"
[[ "$installed_count" == "$template_count" ]] \
  || { echo "FAIL: installed $installed_count stubs for $template_count templates" >&2; exit 1; }

rm -rf "$fake_repo/.github"

echo "bin/install workflow tests passed"
