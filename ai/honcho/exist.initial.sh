#!/usr/bin/env bash
# exist.initial.sh — make the rendered config.toml readable by the honcho image.
#
# Every rendered file is chmod 600 by src/templates.sh, deny-by-default, on the
# stated assumption that "no container runs as a fixed non-root uid" — each one
# either runs as ${EXIST_PUID} (the uid that owns the rendered files) or as
# root, which reads anything. The honcho image breaks that assumption: it ships
# `USER app` (uid 100, verified: `docker exec honcho id`), so 600 files owned by
# uid 1000 are unreadable to it.
#
# What that cost, before this existed: honcho's own log said
# `Failed to load config.toml: [Errno 13] Permission denied` once at boot and
# then fell back to upstream defaults for EVERY model — openai/gpt-5.4-mini with
# no API key. So the whole file was inert (models, ollama endpoints, the 1024
# embedding dimensions, FLUSH_ENABLED) and every LLM call failed with
# "Missing API key for openai model config". The only outward symptom was
# hermes logging `Failed to sync messages to Honcho: An unexpected error
# occurred` on every turn, and cross-session memory quietly not working.
#
# 0644 is safe here: this file carries model names, ollama base URLs and the
# literal string "ollama" as the api_key. The database credentials honcho
# actually needs arrive via DB_CONNECTION_URI in the environment, never through
# this file — keep it that way, and if a real secret ever has to live in
# config.toml, give the container a group instead of widening the mode.
#
# templates.sh names this exact escape hatch ("widen it in that service's own
# exist.initial.sh, where the reason can live"). Idempotent, no sentinel: it
# re-applies on every ./existential.sh run, which is what keeps it true after a
# re-render.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${SCRIPT_DIR}/config.toml"

if [ ! -f "$CONFIG" ]; then
    echo "[honcho] config.toml not rendered yet — nothing to widen."
    exit 0
fi

# The honcho-deriver container shares this file and the same image, so both are
# fixed by the one chmod.
chmod 0644 "$CONFIG"
echo "[honcho] config.toml readable by the image's uid 100 (0644)."
