# Development

## Local checks

Run:

```bash
bin/check
```

The quality check validates catalog boundaries, skill frontmatter, public
capability parity, manifests, generic examples, tracked sensitive-looking
files, and whitespace. GitHub Actions runs the same command for pull requests
and pushes to `main`.

## Installing adapters with bin/install

`bin/install` manages the deployment of dr-agents skills and plugins to
global and per-repo locations.

```bash
# Set up claudio-dr in ~/.claude/, cody-dr in ~/.codex/, and agents CLI in ~/.local/bin/:
bin/install --global

# Apply claudio-dr to a specific repository, with a named profile:
cd /path/to/your-repo
bin/install --repo --profile craft-control

# Check what is currently installed globally and in the current repo:
bin/install --status

# Check the current repo's workflow stubs and reject vendored catalog files:
cd /path/to/your-repo
bin/install
```

Run without a mode, `bin/install` is the consumer-side gate: it reports each
managed workflow stub as present, absent, drifted, or mismatched, and it
reports any catalog `core/` file vendored at the repository root by name and
state (`identical to catalog` or `diverged from catalog`). Both exit non-zero.
Consumers never need a local copy of a `core/` script: the reusable publishers
run against the catalog checkout, so a vendored copy is never executed and
nothing keeps it current. The installer reports such copies and leaves their
removal to the repository owner.

The `--global` mode also copies `bin/agents` to `~/.local/bin/agents` (creating
the directory if needed) and marks it executable, so the `agents` command is
available system-wide without requiring direnv or the catalog directory to be in
`PATH`. `bin/update --global` and `bin/update --all` both delegate to
`bin/install --global`, so `~/.local/bin/agents` stays in sync whenever you
update.

`bin/install --status` reports whether `~/.local/bin/agents` is present
alongside the claudio-dr and cody-dr version information.

The script reads plugin versions from the manifest files
(`plugins/claudio-dr/.claude-plugin/plugin.json` and
`plugins/cody-dr/.codex-plugin/plugin.json`) and includes them in its output
so you can verify which version is active and where it came from.

On a conflict — an existing non-symlink file whose content differs from the
source — the script prints the conflicting paths and both versions, then exits
non-zero without overwriting. Resolve the conflict manually and re-run.

## Testing installed adapters

Validate the Claude distributable plugin before testing it locally:

```bash
claude plugin validate ./plugins/claudio-dr
```

Codex has no standalone plugin-validation command. Run `bin/check` from the
catalog, then load the Cody DR directory in a local session to validate its
installable behavior.

For a local development session, load the plugin directory directly:

```bash
codex --plugin-dir ./plugins/cody-dr
claude --plugin-dir ./plugins/claudio-dr
```

After a Cody DR or Claudio DR change, bump only the affected plugin's patch
version in both its manifest and matching marketplace entry; `bin/check`
verifies that the values match. Reinstall Cody DR from the marketplace root and
start a new Codex thread. For Claudio DR, run `/plugin marketplace update`,
then `/plugin update claudio-dr@dr-agents`.

Do not treat a locally installed plugin as proof that an installation workflow
works; document and validate the fresh-install path as part of each adapter.

## Releases

Release only a merged `main` commit. First update `CHANGELOG.md`, bump every
affected plugin manifest version, run `bin/check`, and merge the release PR.
Then create and push an annotated semantic-version tag and publish the matching
GitHub release from that tag:

```bash
git tag -a vX.Y.Z -m "vX.Y.Z" <merged-main-sha>
git push origin vX.Y.Z
gh release create vX.Y.Z --repo dgaramos/dr-agents --title "vX.Y.Z" --notes-file CHANGELOG.md
```

Use the release notes for that version's section only. Record incompatible
portable-contract changes under `Changed` and explain their compatibility
impact in `docs/compatibility.md`.
