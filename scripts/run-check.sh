#!/usr/bin/env bash
# In-repo gate wrapper. The durable out-of-repo copy lived at
# ~/.hermes/scripts/gate/run-check.sh and only did:
#   cd /mnt/hdd/repo/proton-ge-custom && bash .dbg-ds5/pp-check.sh --check
# This version resolves the repo root from its own location (PWD-independent),
# calls the in-repo gate, and keeps the original log/tail/exit contract.
# Usage: run-check.sh [logfile]
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="${1:-${TMPDIR:-/tmp}/pp-check-now.log}"
mkdir -p "$(dirname "$LOG")"
cd "$root" || exit 1
bash scripts/pp-check.sh --check > "$LOG" 2>&1
rc=$?
echo "EXIT=$rc"
tail -2 "$LOG"
exit "$rc"
