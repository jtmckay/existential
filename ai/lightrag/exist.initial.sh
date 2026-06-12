#!/usr/bin/env bash
# lightrag — pre-startup init
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read LIGHTRAG_NOTES_PATH from the rendered service .env.
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    LIGHTRAG_NOTES_PATH="$(grep -E '^LIGHTRAG_NOTES_PATH=' "$SCRIPT_DIR/.env" | cut -d= -f2-)"
fi

if [[ -z "${LIGHTRAG_NOTES_PATH:-}" ]]; then
    echo "  LIGHTRAG_NOTES_PATH not set — re-run ./existential.sh to configure" >&2
    exit 1
fi

if [[ ! -d "$LIGHTRAG_NOTES_PATH" ]]; then
    echo "  Creating notes directory: $LIGHTRAG_NOTES_PATH"
    mkdir -p "$LIGHTRAG_NOTES_PATH"
else
    echo "  Notes directory exists: $LIGHTRAG_NOTES_PATH"
fi
