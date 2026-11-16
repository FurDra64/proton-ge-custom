# Multi-fork tracking v2 — DESIGN (ratified direction, 2026-11-17)

Goal: track 10–20 forks mechanically, with agents deciding and humans
only setting direction (GOVERNANCE R5/R6).

## Decisions

- D1: `manifest/forks.manifest.yml` v2 is v1-compatible.
  Canonical shape is `forks: [{name, repo, ref, strategy, enabled}]`;
  readers accept the old v1 single-primary shape too.
- D2: `pins/<name>.conf` is shell-sourceable `KEY=VALUE`, one key per line,
  `#` comments allowed. Keys: `NAME, REPO, REF, STRATEGY, ENABLED`.
  A fork with `ENABLED=false` is never fetched — safe to stage unknowns.
- D3: `scripts/drift-check.sh` is read-only. The only network operation
  allowed is `git ls-remote <repo> <ref>` (no fetch, no clone, no write).
  Exit codes: `0` = in sync (CLEAN), `1` = behind/diverged (needs sync),
  `2` = config error (missing manifest/pins/unknown fork).
- D4: CI gate (`fork-drift.yml`) runs with `contents: read` and may open
  issues (`issues: write`) on drift. It never pushes, merges, or opens
  PRs by itself. Auto-merge of sync results is forbidden (SYNC.md).
- D5: secondaries are integrated by cherry-pick onto the primary line,
  never by merge. Primary (`ge-upstream`) merges per SYNC.md contract.

## Layout (proton repo root)

```
manifest/forks.manifest.yml   # fork inventory (v2, v1-compatible)
pins/<name>.conf              # per-fork pins (shell-sourceable)
scripts/drift-check.sh        # read-only drift probe (exit 0/1/2)
tests/test_drift.sh           # 5 contract tests (TDD)
.github/fork-drift.yml        # read-only CI gate
triage/TEMPLATE.md            # drift triage record template
```

## Flow

1. CI (or `drift-check.sh` locally) resolves each enabled fork's pinned
   SHA vs live `HEAD` via `ls-remote`. No state is mutated.
2. `1` (behind) opens/updates an Issue with the triage template;
   an agent (or human, direction-level only) picks it up.
3. Integration follows the fork's strategy (merge for primary,
   cherry-pick for secondaries) through the normal PR + `--check` gates.
4. Resolutions are recorded per GOVERNANCE R7 (docs + Knowledge base).

## Non-goals (v2)

- No auto-sync pushes, no auto-PR creation, no tag tracking.
- Promoting `upstreams.yml` (v1) to the v2 manifest is a separate task.
- Real fork #4..#20 onboarding (list-up + network verify) is separate.
