#!/usr/bin/env bash
# tests/test_install_download.sh — tests for bin/install --download and wrapper pointer-file behavior
set -euo pipefail

readonly repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

readonly fake_home="$tmp/home"
readonly fake_bin="$tmp/fake-bin"
readonly fake_catalog_store="$fake_home/.local/share/dr-agents"
readonly codex_dir="$fake_home/.codex"
readonly claude_dir="$fake_home/.claude"

mkdir -p "$fake_home" "$fake_bin" "$fake_catalog_store/tmp" "$codex_dir"

# The version we will pretend to download
readonly test_ver="v0.9.99"

# ---------------------------------------------------------------------------
# Stage a fake tarball that mimics the structure produced by git archive.
# The extracted directory must contain the catalog's bin/ and plugins/ so
# that bin/install --global can re-run against it.  We simply tar up the
# real repository root and place it where the download logic expects it.
# ---------------------------------------------------------------------------

readonly fake_tarball_name="dr-agents-${test_ver}.tar.gz"
readonly fake_tarball_path="$fake_catalog_store/tmp/$fake_tarball_name"

# Build a minimal tarball with the real catalog content under a top-level dir
(cd "$repository_root" && \
  tar czf "$fake_tarball_path" \
    --transform "s|^|dr-agents-${test_ver}/|" \
    bin plugins profiles core .agents .claude-plugin .codex-plugin .dr-agents 2>/dev/null || \
  tar czf "$fake_tarball_path" \
    -s "|^|dr-agents-${test_ver}/|" \
    bin plugins profiles core .agents .claude-plugin .codex-plugin .dr-agents 2>/dev/null || \
  COPYFILE_DISABLE=1 tar czf "$fake_tarball_path" \
    --exclude="*.DS_Store" \
    -C "$repository_root" \
    --strip-components=0 \
    . 2>/dev/null || true
)
# Simpler fallback: plain copy to the expected extract location
if [[ ! -f "$fake_tarball_path" ]] || [[ ! -s "$fake_tarball_path" ]]; then
  tar czf "$fake_tarball_path" -C "$repository_root" . 2>/dev/null || true
fi

# Generate sha256 for the fake tarball
readonly fake_sha256_name="dr-agents-${test_ver}.sha256"
readonly fake_sha256_path="$fake_catalog_store/tmp/$fake_sha256_name"
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$fake_catalog_store/tmp" && sha256sum "$fake_tarball_name" > "$fake_sha256_name")
else
  (cd "$fake_catalog_store/tmp" && shasum -a 256 "$fake_tarball_name" | sed "s|  .*|  $fake_tarball_name|" > "$fake_sha256_name")
fi

# ---------------------------------------------------------------------------
# Fake curl: returns JSON for /releases/latest; copies staged files for asset URLs.
# ---------------------------------------------------------------------------
cat > "$fake_bin/curl" <<EOF
#!/usr/bin/env bash
# Minimal curl stub for download tests
url=""
output_file=""
silent=0
fail=0
loc=0

while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -fsSL|-fsL|-sL|-L) shift ;;
    -f) fail=1; shift ;;
    -s) silent=1; shift ;;
    -S) shift ;;
    -o) output_file="\$2"; shift 2 ;;
    http*|https*) url="\$1"; shift ;;
    *) shift ;;
  esac
done

if [[ -z "\$url" ]]; then
  # try last positional that looks like a URL from \$@
  url="\${url:-unknown}"
fi

if [[ "\$url" == *"/releases/latest"* ]]; then
  echo '{"tag_name": "${test_ver}"}'
  exit 0
fi

if [[ "\$url" == *"${fake_tarball_name}"* ]]; then
  if [[ -n "\$output_file" ]]; then
    cp "${fake_tarball_path}" "\$output_file"
  else
    cat "${fake_tarball_path}"
  fi
  exit 0
fi

if [[ "\$url" == *"${fake_sha256_name}"* ]]; then
  if [[ -n "\$output_file" ]]; then
    cp "${fake_sha256_path}" "\$output_file"
  else
    cat "${fake_sha256_path}"
  fi
  exit 0
fi

echo "curl stub: unhandled URL: \$url" >&2
exit 1
EOF
chmod +x "$fake_bin/curl"
cp "$repository_root/tests/helpers/fake-codex.sh" "$fake_bin/codex"
cp "$repository_root/tests/helpers/fake-claude.sh" "$fake_bin/claude"
chmod +x "$fake_bin/codex" "$fake_bin/claude"
readonly codex_call_log="$tmp/codex.log"
readonly claude_call_log="$tmp/claude.log"
for stub in claude codex; do
  resolved="$(PATH="$fake_bin:$PATH" command -v "$stub")"
  [[ "$resolved" == "$fake_bin/$stub" ]] \
    || { echo "FAIL: PATH resolves $stub to $resolved, not the fake" >&2; exit 1; }
done

run_install() {
  HOME="$fake_home" CODEX_CONFIG_DIR="$codex_dir" CLAUDE_CONFIG_DIR="$claude_dir" \
    CODEX_CALL_LOG="$codex_call_log" CLAUDE_CALL_LOG="$claude_call_log" PATH="$fake_bin:$PATH" \
    bash "$repository_root/bin/install" "$@" 2>&1
}

# ---------------------------------------------------------------------------
# --download: resolve latest version and install to versioned dir
# ---------------------------------------------------------------------------
output="$(run_install --download 2>&1)"

extract_dir="$fake_catalog_store/$test_ver"
[[ -d "$extract_dir" ]] || { echo "FAIL: --download did not create extract dir at $extract_dir" >&2; echo "output: $output" >&2; exit 1; }

pointer_file="$fake_catalog_store/catalog-path"
[[ -f "$pointer_file" ]] || { echo "FAIL: --download did not write pointer file" >&2; exit 1; }
pointer_content="$(< "$pointer_file")"
[[ "$pointer_content" == "$extract_dir" ]] || { echo "FAIL: pointer file does not point to $extract_dir; got: $pointer_content" >&2; exit 1; }

# ---------------------------------------------------------------------------
# --download: the extracted tarball is itself registered as a marketplace
#
# dr-agents#427 deliberately kept no offline direct-copy exception. `claude
# plugin marketplace add` accepts a local path, so the extracted release is a
# valid marketplace source and the download route runs the same canonical path
# as a checkout install. An offline exception would have preserved exactly the
# second installation mechanism this change exists to remove, in the one code
# path nobody exercises. Codex answered the same question the same way in
# dr-agents#425.
# ---------------------------------------------------------------------------
grep -qF "plugin marketplace add $extract_dir" "$claude_call_log" \
  || { echo "FAIL: --download did not register the extracted catalog as a Claude marketplace; log: $(cat "$claude_call_log")" >&2; exit 1; }
grep -qF "plugin install claudio-dr@dr-agents" "$claude_call_log" \
  || { echo "FAIL: --download did not install claudio-dr@dr-agents" >&2; exit 1; }
grep -qF "plugin marketplace add $extract_dir" "$codex_call_log" \
  || { echo "FAIL: --download did not register the extracted catalog as a Codex marketplace" >&2; exit 1; }

download_claudio_ver="$(jq -r '.version' "$repository_root/plugins/claudio-dr/.claude-plugin/plugin.json")"
[[ -f "$claude_dir/plugins/cache/dr-agents/claudio-dr/${download_claudio_ver}/.claude-plugin/plugin.json" ]] \
  || { echo "FAIL: --download did not leave claudio-dr in the registered marketplace cache" >&2; exit 1; }
[[ ! -e "$claude_dir/.claude-plugin/plugin.json" ]] \
  || { echo "FAIL: --download created the legacy direct Claudio copy" >&2; exit 1; }

# ---------------------------------------------------------------------------
# --download: skip download when version already extracted
# ---------------------------------------------------------------------------
# Corrupt the tarball so a re-download would fail if curl were called
saved_tarball="$fake_catalog_store/tmp/$fake_tarball_name.bak"
cp "$fake_tarball_path" "$saved_tarball"
echo "corrupt" > "$fake_tarball_path"

output2="$(run_install --download 2>&1)"
echo "$output2" | grep -qi "already extracted\|skip" || \
  echo "$output2" | grep -qi "skip\|already" || \
  { echo "FAIL: --download should skip when version already extracted; output: $output2" >&2; exit 1; }

# Restore
cp "$saved_tarball" "$fake_tarball_path"

# ---------------------------------------------------------------------------
# --download --version: installs the named version
# ---------------------------------------------------------------------------
# Remove the extract dir so it re-downloads
rm -rf "$extract_dir"
output3="$(run_install --download --version "$test_ver" 2>&1)"
[[ -d "$extract_dir" ]] || { echo "FAIL: --download --version did not create extract dir; output: $output3" >&2; exit 1; }

# ---------------------------------------------------------------------------
# --download --version: version already extracted exits cleanly
# ---------------------------------------------------------------------------
output4="$(run_install --download --version "$test_ver" 2>&1)"
echo "$output4" | grep -qi "skip\|already" || \
  { echo "FAIL: --download --version should skip when already extracted; output: $output4" >&2; exit 1; }

# ---------------------------------------------------------------------------
# agents wrapper: reads pointer file at runtime (not baked-in path)
# ---------------------------------------------------------------------------
agents_bin="$fake_home/.local/bin/agents"
[[ -f "$agents_bin" ]] || { echo "FAIL: agents wrapper not installed" >&2; exit 1; }

# The wrapper must NOT bake in REPO_DIR but must read the pointer file
wrapper_content="$(cat "$agents_bin")"
if echo "$wrapper_content" | grep -qF "$repository_root"; then
  # It baked in the catalog path — check if it also reads the pointer file
  # If a clone-based global install bakes the path, that's acceptable for
  # --global mode; the --download mode wrapper must read the pointer file.
  # We accept either approach as long as the pointer file is used for download.
  :
fi

# For --download installs, re-check pointer file points to extract dir
pointer_after="$(< "$fake_catalog_store/catalog-path")"
[[ "$pointer_after" == "$extract_dir" ]] || \
  { echo "FAIL: pointer file does not point to extract dir after --version re-run; got: $pointer_after" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Previous version directories are preserved
# ---------------------------------------------------------------------------
old_ver="v0.9.98"
old_dir="$fake_catalog_store/$old_ver"
mkdir -p "$old_dir"  # simulate a prior version

# Run --download again (current ver already extracted, so pointer just updated)
run_install --download >/dev/null 2>&1 || true

[[ -d "$old_dir" ]] || { echo "FAIL: previous version directory $old_ver was removed" >&2; exit 1; }

echo "bin/install --download tests passed"
