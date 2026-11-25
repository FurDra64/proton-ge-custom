#!/bin/bash
# Gate wrapper: run the proton patch gate from the repo root.
#
# Reconstructed from the former scratch wrapper (~/.hermes/cache/scratch/
# run-check.sh), which was only:
#   cd /mnt/hdd/repo/proton-ge-custom && bash .dbg-ds5/pp-check.sh --check
# This version resolves the repo root from its own location (PWD-independent)
# and calls the in-repo copy of the gate.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
exec bash scripts/pp-check.sh --check "$@"
