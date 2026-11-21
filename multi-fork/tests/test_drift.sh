#!/usr/bin/env bash
# Contract tests for multi-fork drift-check (TDD: RED then GREEN).
# 5 tests: behind->1, clean->0, disabled-skip, unknown-fork->2,
# read-only (no fetch/clone/push/checkout in the script).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$ROOT/scripts/drift-check.sh"
MANIFEST="$ROOT/manifest/forks.manifest.yml"

pass=0; fail=0
ok()   { pass=$((pass + 1)); echo "ok: $1"; }
bad()  { fail=$((fail + 1)); echo "NOT OK: $1"; }

# 1. behind -> exit 1 (pinned != live; live always differs from zeros)
if "$CHECK" --manifest "$MANIFEST" --fork ge-upstream \
        --pinned-sha 0000000000000000000000000000000000000000 >/dev/null 2>&1; then
    bad "behind should exit 1"
else
    rc=$?
    if [[ "$rc" == "1" ]]; then ok "behind exits 1"; else bad "behind exit=$rc"; fi
fi

# 2. clean -> exit 0 (pinned == live resolved just now)
live="$(git ls-remote https://github.com/GloriousEggroll/proton-ge-custom.git master | awk '{print $1}')"
if "$CHECK" --manifest "$MANIFEST" --fork ge-upstream \
        --pinned-sha "$live" >/dev/null 2>&1; then
    ok "clean exits 0"
else
    bad "clean should exit 0"
fi

# 3. disabled fork is skipped (exit 0, no network needed for verdict)
if "$CHECK" --manifest "$MANIFEST" --fork cachyos-proton 2>&1 | grep -q SKIP; then
    ok "disabled fork skipped"
else
    bad "disabled fork should SKIP"
fi

# 4. unknown fork -> exit 2
if "$CHECK" --manifest "$MANIFEST" --fork no-such-fork >/dev/null 2>&1; then
    bad "unknown fork should fail"
else
    rc=$?
    if [[ "$rc" == "2" ]]; then ok "unknown fork exits 2"; else bad "unknown exit=$rc"; fi
fi

# 5. read-only: the script must not contain fetch/clone/push/checkout/reset
if grep -nE 'git +(fetch|clone|push|checkout|reset|pull)\b' "$CHECK" | grep -v ls-remote; then
    bad "script contains mutating git command"
else
    ok "script is read-only (ls-remote only)"
fi

# 6. missing manifest -> exit 2
if "$CHECK" --manifest /nonexistent.yml --fork ge-upstream >/dev/null 2>&1; then
    bad "missing manifest should fail"
else
    rc=$?
    if [[ "$rc" == "2" ]]; then ok "missing manifest exits 2"; else bad "missing exit=$rc"; fi
fi

echo "tests: pass=$pass fail=$fail"
[[ "$fail" == "0" ]]
