# scripts/ — proton-side patch gate

Fork-owned helper scripts. Upstream (GloriousEggroll/proton-ge-custom) has no
`scripts/` directory, so files here are never touched by upstream syncs.

| File | Purpose |
|------|---------|
| `pp-check.sh` | Apply-order gate for `patches/` (sections 1, 2-0..2-7). Byte-identical copy of the previously scratch-only gate that OBSOLETE-AUDIT.md calls "the official gate". |
| `run-check.sh` | Thin wrapper: cd to the repo root, then `bash scripts/pp-check.sh --check`. |

## Usage

From the repo root (the wine submodule must be checked out at the pinned commit):

```bash
bash scripts/run-check.sh                 # = pp-check.sh --check
bash scripts/pp-check.sh --check          # same, no wrapper
```

`--check` exports `wine/HEAD` into a temporary shadow directory next to the repo
root, applies the WINE sections (2-0..2-7) there, and removes the shadow on
exit. The working tree is never modified. Known residuals are reported as
`FAILED`; nothing is repaired.

Exit status: `0` = `check passed`, `1` = `check FAILED: N failed, M passed`.
The summary's N counts OBSOLETE rows too — true failures are the `^FAILED`
rows; `^OBSOLETE` rows are "already in tree, needs a removal decision".

## Environment

- `SHADOW_REUSE=<dir>` reuses an existing shadow tree instead of exporting a
  fresh one (much faster when iterating).
- `EMPTY_OK_DIRS` (inside `pp-check.sh`) lists staging directories that are
  legitimately empty; an undeclared empty directory is a failure.
- Network/build steps (`autoreconf`, `make_requests`, mono/dxvk fetch) run only
  without `--check`.

## Provenance

`pp-check.sh` was carried only in the untracked `.dbg-ds5/` debug tree; the
former scratch wrapper `run-check.sh` was deleted when the scratch cache was
pruned, which made the audit in `OBSOLETE-AUDIT.md` non-reproducible. Both are
committed here so the audit can be re-run from a clean clone.
