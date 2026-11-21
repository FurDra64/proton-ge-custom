#!/usr/bin/env bash
# Read-only drift probe for one tracked fork (multi-fork v2, DESIGN.md D3).
# The ONLY network operation allowed is `git ls-remote <repo> <ref>`.
# No fetch, no clone, no checkout, no push, no state mutation.
#
# Usage: drift-check.sh --manifest <file> --fork <name> [--pinned-sha <sha>]
#   --pinned-sha defaults to the local tracking ref for the fork
#   (ge-upstream: origin/master).
# Exit: 0 = in sync (CLEAN), 1 = behind/diverged (needs sync),
#       2 = config error (missing manifest/pins/unknown fork).
set -euo pipefail

MANIFEST=""
FORK=""
PINNED=""

usage() {
    cat <<'EOF'
Usage: drift-check.sh --manifest <file> --fork <name> [--pinned-sha <sha>]
  Probes live HEAD of a tracked fork via `git ls-remote` (read-only).
  Exit 0 = in sync, 1 = drift detected, 2 = config error.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --manifest) MANIFEST="$2"; shift 2 ;;
        --fork) FORK="$2"; shift 2 ;;
        --pinned-sha) PINNED="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ -n "$MANIFEST" && -n "$FORK" ]] || { usage >&2; exit 2; }
[[ -f "$MANIFEST" ]] || { echo "error: manifest not found: $MANIFEST" >&2; exit 2; }

# Resolve REPO/REF/ENABLED for the fork (minimal YAML parse: flat key scan
# within the fork's block; keeps the script dependency-free).
read_repo_ref() {
    local in_block=0
    local name="" repo="" ref="" enabled=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]name:[[:space:]]*(.+) ]]; then
            if [[ -n "$name" && "$name" == "$FORK" ]]; then
                printf '%s\n%s\n%s\n' "$repo" "$ref" "$enabled"
                return 0
            fi
            name="${BASH_REMATCH[1]}"; repo=""; ref=""; enabled=""
            in_block=1
        elif [[ "$in_block" == 1 && "$line" =~ ^[[:space:]]*(repo|ref|strategy|enabled):[[:space:]]*(.+) ]]; then
            case "${BASH_REMATCH[1]}" in
                repo) repo="${BASH_REMATCH[2]}" ;;
                ref) ref="${BASH_REMATCH[2]}" ;;
                enabled) enabled="${BASH_REMATCH[2]}" ;;
            esac
        fi
    done < "$MANIFEST"
    if [[ -n "$name" && "$name" == "$FORK" ]]; then
        printf '%s\n%s\n%s\n' "$repo" "$ref" "$enabled"
        return 0
    fi
    return 1
}

resolved="$(read_repo_ref)" || { echo "error: fork not in manifest: $FORK" >&2; exit 2; }
REPO="$(printf '%s\n' "$resolved" | sed -n '1p')"
REF="$(printf '%s\n' "$resolved" | sed -n '2p')"
ENABLED="$(printf '%s\n' "$resolved" | sed -n '3p')"
[[ -n "$REPO" && -n "$REF" ]] || { echo "error: fork $FORK missing repo/ref" >&2; exit 2; }

if [[ "$ENABLED" != "true" ]]; then
    echo "SKIP fork=$FORK (disabled)"
    exit 0
fi

url="https://github.com/${REPO}.git"
live="$(git ls-remote "$url" "$REF" 2>/dev/null | awk '{print $1}')" || {
    echo "error: ls-remote failed for $REPO $REF" >&2; exit 2
}
[[ -n "$live" ]] || { echo "error: empty ls-remote for $REPO $REF" >&2; exit 2; }

if [[ -z "$PINNED" ]]; then
    # Default pinned state: local tracking ref of the fork.
    case "$FORK" in
        ge-upstream) PINNED="$(git rev-parse origin/master 2>/dev/null || true)" ;;
        *) PINNED="" ;;
    esac
fi
[[ -n "$PINNED" ]] || { echo "error: no pinned SHA for $FORK (pass --pinned-sha)" >&2; exit 2; }

if [[ "$live" == "$PINNED" ]]; then
    echo "CLEAN fork=$FORK sha=$live"
    exit 0
fi
echo "BEHIND fork=$FORK pinned=$PINNED live=$live"
exit 1
