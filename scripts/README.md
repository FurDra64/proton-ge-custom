# scripts/ — proton-side patch gate

Fork-owned helper scripts. Upstream (GloriousEggroll/proton-ge-custom) has no
`scripts/` directory, so files here are never touched by upstream syncs.

| File | Purpose |
|------|---------|
| `pp-check.sh` | Apply-order gate for `patches/` (sections 1, 2-0..2-7). Derived from the untracked `.dbg-ds5/pp-check.sh` that OBSOLETE-AUDIT.md calls "the official gate"; the shadow-tree handling is the only change (see below). |
| `run-check.sh` | Wrapper: `cd` to the repo root, run the gate, print `EXIT=<rc>` plus the last log lines. Adapted from `~/.hermes/scripts/gate/run-check.sh`. |

## Usage

From anywhere (the wrapper resolves the repo root itself). The `wine` submodule
must be checked out at the pinned commit:

```bash
bash scripts/run-check.sh                 # log -> ${TMPDIR:-/tmp}/pp-check-now.log
bash scripts/run-check.sh /tmp/gate.log   # explicit log path
bash scripts/pp-check.sh --check          # gate directly, must be run from the repo root
```

`--check` exports `wine/HEAD` into a shadow git repo, applies the WINE sections
(2-0..2-7) there, and removes the shadow on exit. The working tree is never
modified. Known residuals are reported as `FAILED`; nothing is repaired.

Exit status: `0` = `check passed`, `1` = `check FAILED: N failed, M passed`.
The summary's N counts OBSOLETE rows too — true failures are the `^FAILED`
rows; `^OBSOLETE` rows are "already in tree, needs a removal decision".

## Shadow trees

- Created in `${TMPDIR:-/tmp}/pp-check-XXXXXX/`, with `wine/` holding the export
  and a `patches` symlink back to the repo (the gate reaches the proton patches
  through `../patches`).
- Removed by an EXIT trap. A killed run leaves one behind, so the gate sweeps
  stale `pp-check-*` dirs older than 24h at start, plus any legacy
  `$REPO/.wine-check-*` trees created by older versions (those are also
  `.gitignore`d).

## Environment

- `SHADOW_REUSE=<dir>` reuses an existing shadow tree instead of exporting a
  fresh one (much faster when iterating).
- `EMPTY_OK_DIRS` (inside `pp-check.sh`) lists staging directories that are
  legitimately empty; an undeclared empty directory is a failure.
- Network/build steps (`autoreconf`, `make_requests`, mono/dxvk fetch) run only
  without `--check`.

## Provenance

The gate lived only in the untracked `.dbg-ds5/` debug tree, and the wrapper
used by the gate commands in kanban cards lived in the 24h-pruned scratch dir
(`~/.hermes/cache/scratch/run-check.sh`, since deleted). A durable copy of the
wrapper survives at `~/.hermes/scripts/gate/run-check.sh`; `scripts/run-check.sh`
is that wrapper with the repo root resolved from the script location and the
gate path pointed at this directory. Committing both makes the audit in
`OBSOLETE-AUDIT.md` reproducible from a clean clone.
