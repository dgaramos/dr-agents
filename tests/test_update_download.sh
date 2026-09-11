#!/usr/bin/env bash
# tests/test_update_download.sh — tests for bin/update --download
set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

readonly fake_home="$tmp/home"
readonly fake_bin="$tmp/fake-bin"
readonly fake_catalog_store="$fake_home/.local/share/dr-agents"
readonly codex_dir="$fake_home/.codex"

mkdir -p "$fake_home" "$fake_bin" "$fake_catalog_store/tmp" "$codex_dir"

readonly current_ver="v0.9.10"
readonly newer_ver="v0.9.11"

# Stage a fake tarball for the newer version
readonly newer_tarball_name="dr-agents-${newer_ver}.tar.gz"
readonly newer_tarball_path="$fake_catalog_store/tmp/$newer_tarball_name"
readonly newer_sha256_name="dr-agents-${newer_ver}.sha256"
readonly newer_sha256_path="$fake_catalog_store/tmp/$newer_sha256_name"

tar czf "$newer_tarball_path" -C "$repository_root" . 2>/dev/null || true
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$fake_catalog_store/tmp" && sha256sum "$newer_tarball_name" > "$newer_sha256_name")
else
  (cd "$fake_catalog_store/tmp" && shasum -a 256 "$newer_tarball_name" | sed "s|  .*|  $newer_tarball_name|" > "$newer_sha256_name")
fi

# ---------------------------------------------------------------------------
# Create a simulated "current" downloaded install
# ---------------------------------------------------------------------------
current_extract_dir="$fake_catalog_store/$current_ver"
mkdir -p "$current_extract_dir"
# Copy catalog content so bin/install --global works from it
cp -r "$repository_root/plugins" "$current_extract_dir/"
cp -r "$repository_root/bin" "$current_extract_dir/"
# Write a pointer file pointing to the current version
echo "$current_extract_dir" > "$fake_catalog_store/catalog-path"

# ---------------------------------------------------------------------------
# Fake curl stub
# ---------------------------------------------------------------------------
cat > "$fake_bin/curl" <<EOF
#!/usr/bin/env bash
url=""
output_file=""

while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -fsSL|-fsL|-sL|-L|-f|-s|-S) shift ;;
    -o) output_file="\$2"; shift 2 ;;
    http*|https*) url="\$1"; shift ;;
    *) shift ;;
  esac
done

if [[ "\$url" == *"/releases/latest"* ]]; then
  echo '{"tag_name": "${newer_ver}"}'
  exit 0
fi
if [[ "\$url" == *"${newer_tarball_name}"* ]]; then
  [[ -n "\$output_file" ]] && cp "${newer_tarball_path}" "\$output_file" || cat "${newer_tarball_path}"
  exit 0
fi
if [[ "\$url" == *"${newer_sha256_name}"* ]]; then
  [[ -n "\$output_file" ]] && cp "${newer_sha256_path}" "\$output_file" || cat "${newer_sha256_path}"
  exit 0
fi
echo "curl stub: unhandled URL: \$url" >&2
exit 1
EOF
chmod +x "$fake_bin/curl"

# bin/install --repo installs into the *current working directory*, not into
# HOME, so a faked HOME alone does not contain a stray install: an unrejected
# --repo would write into whatever directory the suite happens to run from,
# which is the catalog checkout itself. Every invocation therefore runs from a
# scratch directory.
readonly scratch_cwd="$tmp/cwd"
mkdir -p "$scratch_cwd"

run_update() {
  ( cd "$scratch_cwd" \
      && HOME="$fake_home" CODEX_CONFIG_DIR="$codex_dir" PATH="$fake_bin:$PATH" \
         bash "$repository_root/bin/update" "$@" 2>&1 )
}

# ---------------------------------------------------------------------------
# --download: newer release available → downloads and updates pointer file
# ---------------------------------------------------------------------------
output="$(run_update --download 2>&1)"

newer_extract_dir="$fake_catalog_store/$newer_ver"
[[ -d "$newer_extract_dir" ]] || { echo "FAIL: --download did not extract newer version; output: $output" >&2; exit 1; }

pointer="$(< "$fake_catalog_store/catalog-path")"
[[ "$pointer" == "$newer_extract_dir" ]] || { echo "FAIL: pointer not updated to $newer_ver; got: $pointer" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Previous version directory preserved
# ---------------------------------------------------------------------------
[[ -d "$current_extract_dir" ]] || { echo "FAIL: previous version dir $current_ver was removed" >&2; exit 1; }

# ---------------------------------------------------------------------------
# --download: already at latest → prints "Already at" and exits 0
# ---------------------------------------------------------------------------
# Now pointer points to newer_ver; update curl to return newer_ver as latest
cat > "$fake_bin/curl" <<EOF
#!/usr/bin/env bash
url=""
output_file=""

while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -fsSL|-fsL|-sL|-L|-f|-s|-S) shift ;;
    -o) output_file="\$2"; shift 2 ;;
    http*|https*) url="\$1"; shift ;;
    *) shift ;;
  esac
done

if [[ "\$url" == *"/releases/latest"* ]]; then
  echo '{"tag_name": "${newer_ver}"}'
  exit 0
fi
echo "curl stub: unhandled URL: \$url" >&2
exit 1
EOF

output2="$(run_update --download 2>&1)"
echo "$output2" | grep -qi "already at" || \
  { echo "FAIL: should print 'Already at' when up to date; output: $output2" >&2; exit 1; }

# ---------------------------------------------------------------------------
# --download: no pointer file → exits non-zero with helpful message
# ---------------------------------------------------------------------------
rm -f "$fake_catalog_store/catalog-path"
if run_update --download 2>/dev/null; then
  echo "FAIL: --download without pointer file should exit non-zero" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Mutually exclusive mode flags
#
# usage() documents --global, --repo, --all and --download as four alternative
# invocations, so no two of them may be combined. The argument loop used to be
# last-wins, which silently resolved every pair to whichever flag came last and
# then executed it: `bin/update --download --global` performed a complete
# global install and exited 0.
#
# These assertions must not be able to pass for an environmental reason. The
# assertion they replace accepted *any* non-zero exit, and a failing
# `git pull --ff-only` supplied one whenever the checkout's branch had no
# configured upstream — so the result was decided by branch configuration
# rather than by bin/update. Each case below therefore asserts the cause and
# not merely the exit status: the message must name both conflicting flags,
# and pull_catalog must never have been reached.
# ---------------------------------------------------------------------------

# Record git invocations instead of performing them. bin/update runs
# `git pull --ff-only` against its own checkout, which must not happen here,
# and an empty log is the direct evidence that rejection precedes the pull.
readonly git_log="$tmp/git-invocations.log"
: > "$git_log"
cat > "$fake_bin/git" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "${git_log}"
exit 0
EOF
chmod +x "$fake_bin/git"

# Sentinel state. A rejected invocation must leave every one of these untouched;
# a silent install is what the last-wins loop actually caused.
echo "sentinel-pointer" > "$fake_catalog_store/catalog-path"
rm -rf "$fake_home/.claude" "$codex_dir" "$fake_home/.local/bin"

readonly mode_flags=(global repo all download)

for first in "${mode_flags[@]}"; do
  for second in "${mode_flags[@]}"; do
    [[ "$first" == "$second" ]] && continue

    if out="$(run_update "--$first" "--$second" 2>&1)"; then
      echo "FAIL: --$first --$second should be rejected as mutually exclusive, but exited 0; output: $out" >&2
      exit 1
    fi

    if ! echo "$out" | grep -qi "mutually exclusive"; then
      echo "FAIL: --$first --$second exited non-zero, but not for the mutually-exclusive reason; output: $out" >&2
      exit 1
    fi

    if ! echo "$out" | grep -q -- "--$first"; then
      echo "FAIL: rejection of --$first --$second does not name --$first; output: $out" >&2
      exit 1
    fi

    if ! echo "$out" | grep -q -- "--$second"; then
      echo "FAIL: rejection of --$first --$second does not name --$second; output: $out" >&2
      exit 1
    fi

    if echo "$out" | grep -q "Pulling latest catalog"; then
      echo "FAIL: --$first --$second reached pull_catalog before rejecting; the result would then depend on whether the branch has an upstream; output: $out" >&2
      exit 1
    fi
  done
done

# Rejection precedes any git invocation at all, for every pair above.
if [[ -s "$git_log" ]]; then
  echo "FAIL: a rejected mode pair still invoked git: $(< "$git_log")" >&2
  exit 1
fi

# No rejected pair installed anything.
pointer_after="$(< "$fake_catalog_store/catalog-path")"
[[ "$pointer_after" == "sentinel-pointer" ]] || \
  { echo "FAIL: a rejected mode pair rewrote the catalog-path pointer; got: $pointer_after" >&2; exit 1; }
[[ ! -d "$fake_home/.claude" ]] || \
  { echo "FAIL: a rejected mode pair installed into ~/.claude" >&2; exit 1; }
[[ ! -d "$codex_dir" ]] || \
  { echo "FAIL: a rejected mode pair installed into the Codex config directory" >&2; exit 1; }
[[ ! -e "$fake_home/.local/bin/agents" ]] || \
  { echo "FAIL: a rejected mode pair installed the agents CLI" >&2; exit 1; }
[[ ! -d "$scratch_cwd/.claude" ]] || \
  { echo "FAIL: a rejected mode pair performed a repo-local install in the working directory" >&2; exit 1; }

# ---------------------------------------------------------------------------
# The pre-existing modifier guards keep their own messages. These are not
# mode-versus-mode conflicts and must not be absorbed by the new one.
# ---------------------------------------------------------------------------
assert_rejected_with() {
  local expected="$1"; shift
  local output
  if output="$(run_update "$@" 2>&1)"; then
    echo "FAIL: $* should be rejected; output: $output" >&2
    exit 1
  fi
  echo "$output" | grep -qF -e "$expected" || \
    { echo "FAIL: $* should be rejected with '$expected'; output: $output" >&2; exit 1; }
}

assert_rejected_with "--force is not valid with --download"    --download --force
assert_rejected_with "--workflows is only valid with --global" --repo --workflows
assert_rejected_with "--profile is not valid with --global"    --global --profile demo

# --workflows is rejected for every mode other than global by a single guard,
# including --download. bin/update used to carry a second, narrower guard for
# the --download/--workflows pair specifically; it was unreachable, because
# this one always fired first.
assert_rejected_with "--workflows is only valid with --global" --download --workflows

# ---------------------------------------------------------------------------
# A repeated identical mode flag is not a conflict. Tightening that would be a
# behavior change nobody asked for, so only the absence of the rejection is
# asserted here; the install path itself is covered by tests/test_update.sh.
# ---------------------------------------------------------------------------
repeat_out="$(run_update --global --global 2>&1 || true)"
if echo "$repeat_out" | grep -qi "mutually exclusive"; then
  echo "FAIL: --global --global is not a mode conflict; output: $repeat_out" >&2
  exit 1
fi

echo "bin/update --download tests passed"
